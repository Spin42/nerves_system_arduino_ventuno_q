defmodule NervesSystemArduinoVentunoQ.InstallerTest do
  use ExUnit.Case, async: true

  alias NervesSystemArduinoVentunoQ.Installer

  @fwup_common Path.expand("../fwup_include/fwup-common.conf", __DIR__)
  @stock_gpt File.read!(Path.expand("fixtures/stock-gpt.txt", __DIR__))

  # Evaluates the define() and define-eval() lines of fwup-common.conf.
  defp fwup_defines do
    @fwup_common
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, defines ->
      cond do
        match = Regex.run(~r/^define\((\w+), (\d+)\)/, line) ->
          [_, name, value] = match
          Map.put(defines, name, String.to_integer(value))

        match = Regex.run(~r/^define\((\w+), \$\{(\w+)\}\)/, line) ->
          [_, name, other] = match
          Map.put(defines, name, Map.fetch!(defines, other))

        match = Regex.run(~r/^define-eval\((\w+), "(.*)"\)/, line) ->
          [_, name, expression] = match

          value =
            expression
            |> String.split("+")
            |> Enum.map(fn term ->
              [_, other] = Regex.run(~r/\$\{(\w+)\}/, term)
              Map.fetch!(defines, other)
            end)
            |> Enum.sum()

          Map.put(defines, name, value)

        true ->
          defines
      end
    end)
  end

  defp nerves_gpt do
    rows =
      Installer.partitions()
      |> Enum.map_join("\n", fn p ->
        "  #{p.number}  #{p.first_sector}  #{p.last_sector}  1.0 GiB  8300  #{p.name}"
      end)

    @stock_gpt
    |> String.split("\n")
    |> Enum.reject(&String.match?(&1, ~r/^\s+(70|71)\s/))
    |> Enum.join("\n")
    |> Kernel.<>("\n" <> rows <> "\n")
  end

  describe "partitions/0" do
    test "match the offsets fwup writes to" do
      defines = fwup_defines()
      [a, b, data] = Installer.partitions()

      assert %{number: 70, name: "rootfs_a"} = a
      assert a.first_sector == defines["ROOTFS_A_PART_OFFSET"]
      assert a.last_sector - a.first_sector + 1 == defines["ROOTFS_A_PART_COUNT"]

      assert %{number: 71, name: "rootfs_b"} = b
      assert b.first_sector == defines["ROOTFS_B_PART_OFFSET"]
      assert b.last_sector - b.first_sector + 1 == defines["ROOTFS_B_PART_COUNT"]

      assert %{number: 72, name: "data"} = data
      assert data.first_sector == defines["APP_PART_OFFSET"]
      assert data.last_sector - data.first_sector + 1 == defines["APP_PART_COUNT"]
    end

    test "leave room for the Nerves environment after the ESP" do
      defines = fwup_defines()
      [a | _] = Installer.partitions()

      esp_end = defines["ESP_PART_OFFSET"] + defines["ESP_PART_COUNT"]
      env_end = defines["UBOOT_ENV_OFFSET"] + defines["UBOOT_ENV_COUNT"]

      assert defines["UBOOT_ENV_OFFSET"] >= esp_end
      assert a.first_sector >= env_end
    end

    test "do not overlap and fit before the last usable sector" do
      partitions = Installer.partitions()

      partitions
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [p, next] -> assert p.last_sector < next.first_sector end)

      assert List.last(partitions).last_sector <= 124_321_758
    end
  end

  describe "sgdisk_args/1" do
    test "replace entries 70 and 71 and add 72, keeping the rest" do
      args = Installer.sgdisk_args("/dev/mmcblk0")

      assert List.last(args) == "/dev/mmcblk0"
      assert "--delete=70" in args
      assert "--delete=71" in args
      assert "--new=70:7081984:11276287" in args
      assert "--change-name=70:rootfs_a" in args
      assert "--new=71:11276288:15470591" in args
      assert "--change-name=71:rootfs_b" in args
      assert "--new=72:15470592:124319743" in args
      assert "--change-name=72:data" in args
      refute Enum.any?(args, &String.match?(&1, ~r/^--(delete|new)=([1-9]|[1-6]\d)(:|$)/))
    end
  end

  describe "layout/1" do
    test "recognises the stock Ubuntu layout" do
      assert Installer.layout(@stock_gpt) == :stock
    end

    test "recognises a board already on Nerves" do
      assert Installer.layout(nerves_gpt()) == :nerves
    end

    test "rejects any other layout" do
      moved_esp = String.replace(@stock_gpt, "6031360         7079935", "6031362         7079935")
      assert {:error, message} = Installer.layout(moved_esp)
      assert message =~ "efi"

      assert {:error, _} = Installer.layout("not a partition table")
    end
  end

  describe "prepare_command/1" do
    test "runs install-prepare.sh as root with the firmware and the sgdisk arguments" do
      command = Installer.prepare_command("/tmp/nerves-install")

      assert String.starts_with?(
               command,
               "sudo sh /tmp/nerves-install/install-prepare.sh /tmp/nerves-install/firmware.fw "
             )

      assert String.ends_with?(command, Enum.join(Installer.sgdisk_args("/dev/mmcblk0"), " "))
    end
  end
end
