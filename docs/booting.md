# Booting

## What was tested

Mainline Linux 7.3.1 (arm64 `defconfig`) with the mainline `qcom/monaco-arduino-monza.dtb` was booted from the stock image's GRUB, with the device tree loaded by GRUB's `devicetree` command and a busybox initramfs (log: `docs/raw/spike-mainline-dt.log`):

- The kernel reports `Machine model: Arduino VENTUNO Q`, the debug UART console works, and the eMMC with all 71 partitions is readable.
- Drivers built as modules in `defconfig` (the USB, PCIe and Ethernet SerDes PHYs, the GPU clock controller, the CPU frequency interconnect paths) leave their consumers deferred until they are loaded. The system's kernel configuration builds these in.

Booting the mainline kernel on the vendor device tree was not tried: its bindings are Qualcomm's downstream ones.

## The scheme

UEFI starts GRUB from the ESP. GRUB loads the kernel and the device tree from the active slot's root filesystem, so the kernel, the device tree and the rootfs change together on every update. Nothing in Qualcomm's partitions changes per update, and UEFI's own A/B slots are not used.

| # | Name | Contents |
|---|---|---|
| 1–68 | Qualcomm | untouched |
| 69 | `efi` | FAT (kept, GUID unchanged): `EFI/BOOT/BOOTAA64.EFI` (GRUB), `grub.cfg`, `grubenv` |
| 70 | `rootfs_a` | squashfs, with `/boot/Image` and `/boot/monaco-arduino-monza.dtb` |
| 71 | `rootfs_b` | the same, for slot B |
| 72 | `data` | f2fs, mounted at `/root` |

Partitions 70 and 71 replace `persist` (empty) and `system`; 72 uses the last free GPT entry, so the 72-entry table is kept.

GRUB reads squashfs (`squash4`) and keeps its slot state in `grubenv` on the ESP, as `nerves_system_x86_64` does: the active slot, whether it is validated, and whether an unvalidated slot has already booted once, so an image that never calls `Nerves.Runtime.validate_firmware/0` falls back on the next boot. The Nerves key-value store (`Nerves.Runtime.KV`) follows `nerves_system_x86_64` too.

UEFI's `Boot0000` points at `\EFI\ubuntu\shimaa64.efi` on partition 69. Provisioning either installs GRUB at that path as well or replaces the boot entry; `EFI/BOOT/BOOTAA64.EFI` is the fallback either way.

## Installing

The first install has two candidates, chosen in Task 4:

- **From the stock image:** Ubuntu's GRUB boots a provisioning initramfs once (as the spike did), which repartitions 70 to 72, writes the firmware and replaces the ESP's contents. It needs no Qualcomm boot firmware bundle.
- **Over EDL** with `qdl`, as the UNO Q system does. It needs Qualcomm's boot firmware and partition files for the board.

Recovery is over EDL either way: Arduino's flasher restores the stock image.
