# Arduino VENTUNO Q System

This is the base Nerves System configuration for the
[Arduino VENTUNO Q](https://www.arduino.cc/product-ventuno-q/): a Qualcomm
Dragonwing IQ-8275 (QCS8275) with an STM32H5F5 microcontroller.

| Feature        | Description                                                        |
| -------------- | ------------------------------------------------------------------ |
| CPU            | 4× Cortex-A78C and 4× Cortex-A55                                   |
| Memory         | 16 GB LPDDR5                                                       |
| Storage        | 64 GB eMMC                                                         |
| Linux kernel   | Mainline 7.3.1 with the patches in `linux/`                        |
| Bootloader     | Qualcomm UEFI, then GRUB (arm64 EFI) from the ESP                  |
| IEx terminal   | Debug UART `ttyMSM0` on JCTL (1.8 V, 115200 8N1)                   |
| Ethernet       | Up to 2.5 Gbps (QCA8081, SGMII or 2500BASE-X); `eth0`              |
| USB            | Ethernet gadget (`usb0`) on the USB-C port                         |
| GPU            | Adreno 623: Mesa (freedreno, Turnip), Vulkan 1.3                   |
| NPU            | Hexagon v75 CDSP over FastRPC; the QAIRT runtime is not included   |
| Cameras        | Raspberry Pi Global Shutter and HQ cameras on 3 CSI connectors     |
| Wi-Fi          | QCA2066 over PCIe (ath11k), `wlan0`                                |
| Bluetooth      | QCA2066 over UART (`hci_uart`), `hci0`                             |
| Fan, LEDs      | EMC2305 fan on the CPU thermal zone; PCA9635 for the 4 RGB LEDs    |
| CAN            | 3× CAN FD on the STM32H5F5, as SocketCAN `can0` to `can2` (gs_usb) |
| Audio          | HDMI through the ADV7535 bridge; MAX98091 codec, untested          |
| Display        | Not supported                                                      |

See [docs/booting.md](docs/booting.md) for the boot chain and the eMMC layout,
and [docs/stock-image.md](docs/stock-image.md) for what Arduino's image does on
the board.

## Using

Add the system to your Nerves project's dependencies:

```elixir
{:nerves_system_arduino_ventuno_q,
 github: "Spin42/nerves_system_arduino_ventuno_q",
 tag: "v0.1.1",
 runtime: false,
 targets: :arduino_ventuno_q,
 nerves: [compile: false]}
```

Then build firmware with `MIX_TARGET=arduino_ventuno_q mix firmware`.

## Installing Nerves on a board

A board fresh from Arduino runs Ubuntu. `mix firmware.install` installs Nerves
from it over SSH:

```sh
MIX_TARGET=arduino_ventuno_q mix firmware
MIX_TARGET=arduino_ventuno_q mix firmware.install arduino@<board-ip>
```

The board's user needs key-based SSH and passwordless `sudo`. The task checks
that the eMMC has Arduino's partition table, rewrites partitions 70 to 72
(Ubuntu's `persist` and `system`), reformats the ESP with 512-byte FAT
sectors, puts GRUB and an installer there, and reboots the board. The installer
writes the firmware from RAM and reboots into Nerves. Ubuntu is erased.

Follow the install on the debug UART. The first boot formats the 55 GB
application partition, which takes about two minutes.

After that, update the board with `mix upload`. `Nerves.Runtime.poweroff/0`
turns the board off; it starts again when its power supply is reconnected.
To go back to Ubuntu, flash Arduino's image over EDL with Arduino's flasher:
pull JCTL pin 2 low and reboot.

## Debug UART

JCTL is the 2×5 header above the M.2 slot. Pin 1 is at its right end, in the
row nearer the board's top edge, with the ports facing you.

| JCTL pin | Signal                       | 1.8 V adapter |
| -------- | ---------------------------- | ------------- |
| 1        | GND                          | GND           |
| 4        | TX (board to host)           | RX            |
| 6        | RX (host to board)           | TX            |
| 2        | `FORCED_USB_BOOT_N` (EDL)    | –             |
| 9        | +1.8 V out, do not connect   | –             |

An adapter powered from the host drives the board's RX pin while the board is
off and powers part of it through that pin. The next power on can then leave
the PCIe USB 3 controller off the bus, with link training errors at its switch
port. Connect the adapter once the board is on and disconnect it before
removing power.

## Ethernet

The QCA8081 PHY runs SGMII up to 1 Gbps and 2500BASE-X at 2.5 Gbps and
switches between them with the link speed. Mainline's ETHQOS glue only
reports the device tree's `2500base-x` to phylink, which limits the PHY to
2.5 Gbps; `linux/0006` reports both. After a switch from SGMII to 2500BASE-X
on a running interface the MAC passes no frames until it is reset, so
`linux/0007` reopens the interface after that switch (logged as "restarting
after the switch to 2500BASE-X"). The port links at 10 Mbps to 2.5 Gbps.

The SerDes takes its 0.9 V from the LDO that also feeds the display PHYs.
Mainline's SoM device tree gives the SerDes a deprecated `phy-supply` its
driver ignores, so with no HDMI display that LDO was turned off and Ethernet
stopped; `linux/0010` gives the SerDes its `vdda-0p9` and `vdda-1p2` supplies.
It also ended the stall where, on about one boot in three, the MAC received
no frames after the first link up.

[docs/ethernet.md](docs/ethernet.md) has the details.

The MAC address is derived from the SoC serial number
(`/sys/devices/soc0/serial_number`); the board stores none.

## Wi-Fi and Bluetooth

The QCA2066 module's Wi-Fi sits behind the PCIe switch on PCIe0, with the
USB 3 controller. `linux/0012` holds its enable GPIOs high from boot: the
switch enumerates only then. Mainline maps only two PCIe requester IDs to the
SMMU, so DMA from behind the switch faulted; `linux/0013` maps all of them
and `linux/0014` (from upstream) makes the PCIe driver read that map with the
SMMU's two-cell stream IDs. Configure `wlan0` with VintageNet.

The USB 3 controller on the same switch, a TI TUSB7340, produces a stream of
receiver errors on its link in ASPM L0s, which the root port escalates to
uncorrectable errors; `linux/0016` disables L0s for it and keeps L1.

Bluetooth runs on its own UART. The system ships the Bluetooth patch and the
NVM file for the board's module (`hpnv21g.30c`) and the ath11k firmware, all
from `linux-firmware`.

## Fan and LEDs

The EMC2305 at 0x2f on CCI1 bus 1 drives the fan as the cooling device of the
CPU thermal zone; `hwmon` reports its speed. Mainline's driver never programs
the PWM frequency, which left the fan whining at 2.441 kHz; `linux/0015` sets
the 26 kHz the device tree asks for.

The PCA9635 at 0x22 on the same bus drives the four RGB LEDs, exposed as
`red:indicator-N`, `green:indicator-N` and `blue:indicator-N` (N from 0 to 3)
under `/sys/class/leds`. They light only with push-pull outputs, which
`linux/0011` selects.

## Audio

The sound card has two playback PCMs, which `ventuno-q-audio` routes once the
ADSP has registered the card, about 15 seconds after power on:

| PCM      | Stream      | LPASS port       | Output                         |
| -------- | ----------- | ---------------- | ------------------------------ |
| `hw:0,0` | MultiMedia1 | `LPI_MI2S_RX_4`  | HDMI, through the ADV7535      |
| `hw:0,1` | MultiMedia2 | `LPI_MI2S_RX_0`  | MAX98091 headphone output      |

```sh
aplay -D hw:0,0 file.wav
```

The HDMI audio comes from the ADV7535 DSI-to-HDMI bridge over I2S, not from
the DisplayPort controller (`DISPLAY_PORT_RX_0` fails to start). The
headphone output starts at `Headphone Volume` 15 (-17 dB); `amixer -c0`
sets it from 0 to 31. The board has no audio jack: the JMISC connector
carries headphone (pins 36 to 42), line (32, 34) and earpiece (28, 30)
outputs for an expansion board.

## Microcontroller and CAN

The STM32H5F5 is a USB device of the SoC's second USB controller, which
`linux/0017` powers. Arduino's firmware on it, a Zephyr loader and a sketch,
exposes its three FDCAN controllers as a gs_usb adapter (`can0` to `can2`)
and a CDC ACM serial port (`ttyACM0`) for Arduino's RPC bridge.

The loader starts the sketch only once Linux signals it: GPIO 95 high, which
`linux/0018` holds from boot (until then the LED matrix plays the boot
animation), and a start value in the MCU's backup SRAM, which
`ventuno-q-mcu` writes over SWD at boot, restarting the sketch so that it
registers its Bridge methods with the router the boot starts. The CAN interfaces appear about
13 seconds after power on.

```sh
ip link set can0 type can bitrate 500000
ip link set can0 up
candump can0
```

The system ships the loader of Arduino's Zephyr core `arduino:zephyr` 1.1.0
(`/usr/share/ventuno-q/mcu-loader.bin`), which `ventuno-q-mcu` writes at boot
when flash holds another. Sketches link against the loader, so build them with
that core version. `ventuno-q-mcu flash` writes a sketch, then restarts it; an
image already in flash is verified and not written again:

```sh
arduino-cli compile --fqbn arduino:zephyr:ventunoq --output-dir build .
ventuno-q-mcu flash build/sketch.ino.elf-zsk.bin
```

[ArduinoRouterEx](https://github.com/Spin42/arduino_router_ex) talks to the
sketch's Bridge from Elixir and installs sketches with this command.

The SWD port is wired to SoC GPIOs (SWCLK 71, SWDIO 70, NRST 78). The system
includes STMicroelectronics' OpenOCD, as mainline OpenOCD does not support
the STM32H5:

```sh
openocd -f /usr/share/ventuno-q/mcu-swd.cfg -c init -c "flash probe 0" -c shutdown
```

GPIO 47 drives the STM32's BOOT0 through a level shifter that holds it high
when undriven; `linux/0019` holds it low so that any reset of the MCU starts
the loader rather than ST's ROM bootloader (USB DFU, `0483:df11`, which
`dfu-util` drives).

## GPU

`vulkaninfo --summary` lists the Adreno 623 through Turnip, and
`vk-compute-check` runs a compute shader and checks its output.

## NPU

The system includes the open parts of the stack: the kernel's FastRPC driver,
the FastRPC userspace (`libcdsprpc`) and the board's CDSP firmware and DSP
libraries from `linux-firmware` and
[dsp-binaries](https://github.com/linux-msm/dsp-binaries). Qualcomm's AI
Runtime (QAIRT) is not redistributed. `scripts/fetch-qairt.sh` downloads it
from Qualcomm, checks it and writes the parts the board needs into a rootfs
overlay; downloading it accepts Qualcomm's licence:

```sh
deps/nerves_system_arduino_ventuno_q/scripts/fetch-qairt.sh rootfs_overlay_qairt
```

Add the directory to your firmware's overlays:

```elixir
config :nerves, :firmware, rootfs_overlay: ["rootfs_overlay", "rootfs_overlay_qairt"]
```

The runtime lands in `/opt/qairt`. `npu-check` runs a QNN model on the HTP with
it:

```sh
npu-check /path/to/libmodel.so --input_list inputs.txt --output_dir /root/out
```

HTP models run in an unsigned protection domain; no per-board signature is
needed.

## Kernel command line

`grub.cfg` on the ESP is written once, at install. It sources `/boot/slot.cfg`
from the slot it boots, which sets the kernel command line, so the command
line changes with each firmware update. The kernel log goes to the HDMI
framebuffer (`tty1`) and the debug UART; IEx stays on the UART.

## Cameras

| Camera                             | Sensor | Device tree name |
| ---------------------------------- | ------ | ---------------- |
| Raspberry Pi Global Shutter Camera | IMX296 | `imx296`         |
| Raspberry Pi HQ Camera             | IMX477 | `imx477`         |

The board has three camera connectors with the Raspberry Pi 5 pinout: use
22-to-15-pin Pi 5 camera cables. Each has its own CSIPHY and I2C bus:

| Connector       | CSI     | I2C bus    |
| --------------- | ------- | ---------- |
| Camera 0 (J3_2) | CSIPHY0 | CCI0 bus 0 |
| Camera 1 (J3_3) | CSIPHY1 | CCI1 bus 0 |
| Camera 2 (J3_1) | CSIPHY2 | CCI2 bus 0 |

Both sensors answer at the same I2C address, so the cameras cannot be probed:
your project names the camera on each connector, Camera 0 to Camera 2, in
`/boot/cameras.cfg`, through its rootfs overlay:

```sh
# rootfs_overlay/boot/cameras.cfg
set ventuno_q_cameras=imx296-none-imx477
```

Each field is `none`, `imx296` or `imx477`. The system ships a device tree for
every combination, built from one overlay per connector and sensor
(`linux/0020`), and `/boot/slot.cfg` boots the one the file names. Without the
file, the device tree describes no camera. Two Global Shutter Cameras on
Camera 0 and Camera 1 with an HQ Camera on Camera 2 is the combination tested
on hardware.

CAMSS delivers raw Bayer frames; there is no ISP.

The board passes each connector's I2C lines through a TXS0108 level
translator and drives its enable pin (pin 17) through a TXS0104, which holds
a high level only through about 10 kΩ. The camera I2C buses therefore run at
100 kHz, as on Raspberry Pi boards, and the CSI0 and CSI1 lanes are routed to
J3_2 and J3_3 rather than the JMEDIA header (GPIO 24 and 41). The HQ Camera
works as is. The Global Shutter Camera does not power up on that weak enable:
give it a 1 kΩ resistor between pins 15 (3.3 V) and 11 (enable) of its 15-pin
connector. Its overlay keeps the connector powered so that the board never
drives the enable low against that resistor.

Mainline CAMSS links its sensors only once every sensor in the device tree has
probed, so one missing camera disables all three. `linux/0008` links each
sensor as it probes: the cameras that are plugged in work.

A sensor streams from its CSIPHY through any free CSID and the VFE of the same
index: CSID 0 and 1 are full, 2 to 6 are lite, and all deliver raw frames
(the lite ones need `linux/0009`). For an HQ Camera on Camera 2 at 1332×990
through CSID 0:

```sh
media-ctl -l '"msm_csiphy2":1->"msm_csid0":0[1],"msm_csid0":1->"msm_vfe0_rdi0":0[1]'
media-ctl -V '"imx477 3-001a":0[fmt:SRGGB10_1X10/1332x990]'
media-ctl -V '"msm_csiphy2":0[fmt:SRGGB10_1X10/1332x990],"msm_csid0":0[fmt:SRGGB10_1X10/1332x990],"msm_vfe0_rdi0":0[fmt:SRGGB10_1X10/1332x990]'
v4l2-ctl -d /dev/video2 --set-fmt-video=width=1332,height=990,pixelformat=pRAA
v4l2-ctl -d /dev/video2 --stream-mmap --stream-count=10 --stream-to=/root/hq.raw
```

The sensor's I2C bus number, in its entity name, can change between boots:
`media-ctl -p` lists it.

Each sensor's V4L2 subdevice exposes its controls (`v4l2-ctl -d
/dev/v4l-subdevN -L` lists them with their ranges):

| Control                              | IMX296 | IMX477 |
| ------------------------------------ | ------ | ------ |
| Exposure, analogue gain              | ✓      | ✓      |
| Digital gain                         |        | ✓      |
| Vertical blanking (frame length)     | ✓      | ✓      |
| Horizontal and vertical flips        | ✓      | ✓      |
| Test patterns                        | ✓      | ✓      |
| Crop (`media-ctl` `crop:`)           | ✓      |        |
| Sensor modes (format sizes)          | 1456×1088 | 4056×3040, 4056×2160, 2028×1520, 2028×1080, 1332×990 |

Flips change the Bayer order of the format, and are refused while
streaming. The IMX296 crops in steps of 4 pixels down to 96×88, which
raises its frame rate. The IMX477 also takes the module parameters
`dpc_enable` (on-sensor defect correction) and `fstrobe_enable`,
`fstrobe_cont_trig`, `fstrobe_width` and `fstrobe_delay` (its flash
strobe output).

### External trigger

Both sensor drivers can take their frame timing from an external pulse, set
by their `trigger_mode` module parameter before streaming:

| Sensor | Parameter        | Input | Behaviour                                                              |
| ------ | ---------------- | ----- | ---------------------------------------------------------------------- |
| IMX296 | `trigger_mode=1` | XTR   | Each low pulse starts a frame; the exposure is the low time + 14.26 µs |
| IMX477 | `trigger_mode=2` | XVS   | Each falling edge starts a readout; the exposure is the sensor's own   |

```sh
echo 1 > /sys/module/imx296/parameters/trigger_mode
echo 2 > /sys/module/imx477/parameters/trigger_mode
```

A sensor node's `trigger-mode` device tree property, with the same values,
overrides the parameter for that sensor.

An IMX296 in trigger mode delivers no frame until XTR pulses. Give an IMX477
a frame length slightly shorter than the trigger period. `linux/0021` adds
the IMX296 mode; the IMX477 driver from `linux/0002` has it.

Both inputs idle high. XTR takes 1.8 V logic and the HQ Camera's XVS pad at
most 1.65 V: drive them from a 3.3 V output through a divider, and on a
Global Shutter Camera with a Q2 transistor fitted, remove R11 first.

The board's microcontroller can produce both pulses from one timer, at the
same rate and phase, on D3 and D5 (`ArduinoRouterEx.PulseTrain` in
[arduino_router_ex](https://github.com/Spin42/arduino_router_ex)). Those pins
are inputs until the pulses start: the divider then pulls the camera input
low, so drive the pin high first if the camera must not see a low trigger
before it streams.
