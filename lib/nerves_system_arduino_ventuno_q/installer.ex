defmodule NervesSystemArduinoVentunoQ.Installer do
  @moduledoc """
  The eMMC partition table Nerves uses on the VENTUNO Q, and how it is made
  from the stock Ubuntu one.

  Qualcomm's GPT has 72 entries. Entries 1 to 69 (the boot chain and the ESP)
  are kept. Ubuntu's `persist` (70) and `system` (71) are replaced by the two
  root filesystems, and the last free entry becomes the application
  partition. The Nerves environment sits between the ESP and `rootfs_a`,
  outside any partition. The offsets must match `fwup_include/fwup-common.conf`.
  """

  @esp %{number: 69, name: "efi", first_sector: 6_031_360, last_sector: 7_079_935}
  @stock_tail [
    %{number: 70, name: "persist", first_sector: 7_079_936, last_sector: 7_141_375},
    %{number: 71, name: "system", first_sector: 7_141_376, last_sector: 124_321_758}
  ]
  @partitions [
    %{number: 70, name: "rootfs_a", first_sector: 7_081_984, last_sector: 11_276_287},
    %{number: 71, name: "rootfs_b", first_sector: 11_276_288, last_sector: 15_470_591},
    %{number: 72, name: "data", first_sector: 15_470_592, last_sector: 124_319_743}
  ]

  @typedoc "A GPT entry, with inclusive sector bounds."
  @type partition :: %{
          number: pos_integer(),
          name: String.t(),
          first_sector: non_neg_integer(),
          last_sector: non_neg_integer()
        }

  @doc "The partitions Nerves adds, in order."
  @spec partitions() :: [partition()]
  def partitions, do: @partitions

  @doc """
  Arguments for `sgdisk` that turn the stock table on `device` into the
  Nerves one.
  """
  @spec sgdisk_args(Path.t()) :: [String.t()]
  def sgdisk_args(device) do
    deletes = Enum.map(@stock_tail, &"--delete=#{&1.number}")

    creates =
      Enum.flat_map(@partitions, fn p ->
        [
          "--new=#{p.number}:#{p.first_sector}:#{p.last_sector}",
          "--typecode=#{p.number}:8300",
          "--change-name=#{p.number}:#{p.name}"
        ]
      end)

    deletes ++ creates ++ [device]
  end

  @doc """
  The command, run over SSH, that prepares the stock image and reboots into
  the installer. `remote_dir` holds `install-prepare.sh`, `installer-init` and
  `firmware.fw`. The sgdisk arguments contain no shell metacharacters.
  """
  @spec prepare_command(Path.t()) :: String.t()
  def prepare_command(remote_dir) do
    Enum.join(
      [
        "sudo sh",
        Path.join(remote_dir, "install-prepare.sh"),
        Path.join(remote_dir, "firmware.fw")
        | sgdisk_args("/dev/mmcblk0")
      ],
      " "
    )
  end

  @doc """
  Classifies the output of `sgdisk -p` for the eMMC: `:stock` for Arduino's
  Ubuntu layout, `:nerves` for a board already installed.
  """
  @spec layout(String.t()) :: :stock | :nerves | {:error, String.t()}
  def layout(sgdisk_output) do
    entries = parse(sgdisk_output)

    cond do
      entries == %{} ->
        {:error, "no partition table found in the sgdisk output"}

      not matches?(entries, [@esp]) ->
        {:error, "partition 69 is not the expected efi partition at sector #{@esp.first_sector}"}

      matches?(entries, @stock_tail) and not Map.has_key?(entries, 72) ->
        :stock

      matches?(entries, @partitions) ->
        :nerves

      true ->
        {:error, "partitions 70 to 72 match neither the stock Ubuntu nor the Nerves layout"}
    end
  end

  defp parse(output) do
    for line <- String.split(output, "\n"),
        [_, number, first, last, name] <-
          [Regex.run(~r/^\s*(\d+)\s+(\d+)\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s*$/, line)],
        into: %{} do
      number = String.to_integer(number)

      {number,
       %{
         number: number,
         name: name,
         first_sector: String.to_integer(first),
         last_sector: String.to_integer(last)
       }}
    end
  end

  defp matches?(entries, expected) do
    Enum.all?(expected, &(Map.get(entries, &1.number) == &1))
  end
end
