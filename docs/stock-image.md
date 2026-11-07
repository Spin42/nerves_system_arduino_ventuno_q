# The stock image

What Arduino's Ubuntu 24.04.4 image (kernel `6.8.0-1078-qcom`) does on the VENTUNO Q, recorded by `scripts/survey-stock-image.sh`. The raw survey and serial logs are not in the repository: they carry the board's serial number.

## SoC

| | |
|---|---|
| CPUs | 4× Cortex-A55 (`0xd05`) and 4× Cortex-A78C (`0xd4b`) |
| RAM | 16 GB, 15.6 GB available to Linux |
| Chip | `QCS_MONACO_INDUSTRIAL` 1.0, platform IOT subtype 4 |
| Hypervisor | Gunyah: Linux runs at EL1 |

## Boot chain

1. XBL, from `xbl_a`/`xbl_b`.
2. UEFI 6.0 (`BOOT.MXF.1.0.c1-00460-KODIAKLA-1`), from `uefi_a`/`uefi_b`. It looks for `qclinux_fit.img`, falls back to the legacy multi-DTB in `dtb_a` (`qcom,monaco-monza`, Qualcomm's vendor device tree), and adds `qcom,platform-parts-info` and storage status fixups.
3. UEFI boot entry `Boot0000`: `\EFI\ubuntu\shimaa64.efi` on partition 69 (`efi`, GPT GUID `278e862b-5d8a-becf-1718-9b9731c06c8c`). Secure Boot is disabled and the platform is in Setup Mode.
4. shim, then GRUB 2.12 (`grubaa64.efi`), which reads `/boot/grub/grub.cfg` from partition 71 and shows its menu on the serial console.
5. The kernel's EFI stub, using the device tree from the UEFI configuration table.

The kernel command line is `console=ttyMSM0,115200n8 pcie_pme=nomsi earlycon video=LVDS-1:d`.

## eMMC

59.3 GiB, 512-byte sectors, a GPT with 72 entries of which 71 are used. Partitions 1 to 68 are Qualcomm's (boot firmware in A/B pairs, `dtb_a`/`dtb_b`, `uefivarstore`, logs). The end of the disk:

| # | Name | Start sector | Size | Contents |
|---|---|---|---|---|
| 69 | `efi` | 6031360 | 512 MiB | FAT, label `system-boot`: shim, GRUB |
| 70 | `persist` | 7079936 | 30 MiB | ext4, empty |
| 71 | `system` | 7141376 | 55.9 GiB | ext4, label `writable`: Ubuntu's root |

`emac` (partition 42) is all zeros: the Ethernet MAC address is not stored. `mmcblk0boot0` and `mmcblk0boot1` are 32 MiB each.

## Peripherals

- Ethernet: `end0`, driver `qcom-ethqos`.
- Wi-Fi: `wlp3s0`, `ath11k_pci` (QCA2066 on PCIe).
- CAN: `can0`, `can1` and `can2`, driver `gs_usb`. The STM32H5F5's stock firmware is a USB CAN adapter.
- The remote processors and FastRPC are in use: `adsprpcd` and `cdsprpcd` run, and the `fastrpc` group exists.

## The vendor and mainline device trees

The vendor tree UEFI passes (`qcom,monaco-monza`, 14 674 lines decompiled) is not the mainline `monaco-arduino-monza.dtb` (`arduino,monza`, `qcom,qcs8300`, 8 156 lines). The kernel takes the memory map from UEFI rather than from the device tree's `memory` node, which UEFI leaves empty. The vendor tree's only board-specific fixup the system would miss is `qcom,platform-parts-info`, which carries the chip serial number.
