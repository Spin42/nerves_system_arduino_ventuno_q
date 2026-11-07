defmodule Mix.Tasks.Firmware.Install do
  @shortdoc "Installs Nerves on a VENTUNO Q running Arduino's Ubuntu image"

  @moduledoc """
  Installs the project's firmware on a VENTUNO Q that runs Arduino's stock
  Ubuntu image, over SSH.

      MIX_TARGET=arduino_ventuno_q mix firmware.install arduino@192.168.1.42

  The board's user needs key-based SSH and passwordless `sudo`. The task
  rewrites eMMC partitions 70 to 72 (Ubuntu's `persist` and `system`), puts
  GRUB and an installer on the ESP and reboots the board into it; the
  installer writes the firmware and reboots into Nerves. Watch the debug UART
  (JCTL pins 4 and 6, 1.8 V, 115200 8N1) to follow it. Ubuntu is erased.

  Once Nerves runs, update it with `mix upload`. To go back to Ubuntu, flash
  Arduino's image over EDL with Arduino's flasher.

  ## Options

    * `--firmware PATH` - the `.fw` to install (default: the project's)
    * `--identity PATH` - the SSH private key to use
    * `--yes` - do not ask for confirmation
  """

  use Mix.Task

  alias NervesSystemArduinoVentunoQ.Installer

  @scripts_dir Path.expand("../../../scripts", __DIR__)
  @remote_dir "/tmp/nerves-install"

  @impl Mix.Task
  def run(args) do
    {options, positional} =
      OptionParser.parse!(args, strict: [firmware: :string, identity: :string, yes: :boolean])

    destination =
      case positional do
        [destination] -> destination
        _ -> Mix.raise("Usage: mix firmware.install [options] user@host")
      end

    firmware = options[:firmware] || default_firmware()

    unless File.regular?(firmware) do
      Mix.raise("Firmware not found at #{firmware}. Run `mix firmware` first.")
    end

    ssh_options = ssh_options(options[:identity])

    case Installer.layout(ssh!(ssh_options, destination, "sudo -n sgdisk -p /dev/mmcblk0")) do
      :stock ->
        :ok

      :nerves ->
        Mix.raise(
          "#{destination} already has the Nerves partitions. Update it with `mix upload`."
        )

      {:error, reason} ->
        Mix.raise("Refusing to install on #{destination}: #{reason}")
    end

    unless options[:yes] ||
             Mix.shell().yes?(
               "This erases Ubuntu on #{destination} and installs #{firmware}. Continue?"
             ) do
      Mix.raise("Aborted")
    end

    ssh!(ssh_options, destination, "rm -rf #{@remote_dir} && mkdir -p #{@remote_dir}")

    scp!(ssh_options, destination, [
      {firmware, "firmware.fw"},
      {Path.join(@scripts_dir, "install-prepare.sh"), "install-prepare.sh"},
      {Path.join(@scripts_dir, "installer-init"), "installer-init"}
    ])

    Mix.shell().info("Preparing the installer on #{destination}")
    # The board reboots at the end, which can drop the connection.
    {output, _status} = ssh(ssh_options, destination, Installer.prepare_command(@remote_dir))
    Mix.shell().info(output)

    cond do
      output =~ "Rebooting into the installer" ->
        :ok

      output =~ "Reformatting the ESP" ->
        Mix.raise("""
        Preparing the installer failed after the ESP was reformatted; see the
        output above. Do not reboot the board: it would boot neither Ubuntu nor
        Nerves. Fix the cause and run mix firmware.install again.
        """)

      true ->
        Mix.raise(
          "Preparing the installer failed before any change to the board; see the output above."
        )
    end

    Mix.shell().info("""
    The board is rebooting into the installer, then into Nerves. Follow it on
    the debug UART; it is done when the IEx prompt appears.
    """)
  end

  defp default_firmware do
    app = Mix.Project.config()[:app]
    Path.join([Mix.Project.build_path(), "nerves", "images", "#{app}.fw"])
  end

  defp ssh_options(nil), do: ["-o", "BatchMode=yes"]
  defp ssh_options(identity), do: ["-o", "BatchMode=yes", "-i", Path.expand(identity)]

  defp ssh(ssh_options, destination, command) do
    System.cmd("ssh", ssh_options ++ [destination, command], stderr_to_stdout: true)
  end

  defp ssh!(ssh_options, destination, command) do
    case ssh(ssh_options, destination, command) do
      {output, 0} ->
        output

      {output, status} ->
        Mix.raise("`#{command}` failed on #{destination} (#{status}):\n#{output}")
    end
  end

  defp scp!(ssh_options, destination, files) do
    Enum.each(files, fn {source, name} ->
      target = "#{destination}:#{Path.join(@remote_dir, name)}"

      case System.cmd("scp", ssh_options ++ ["-q", source, target], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, status} -> Mix.raise("Copying #{source} failed (#{status}):\n#{output}")
      end
    end)
  end
end
