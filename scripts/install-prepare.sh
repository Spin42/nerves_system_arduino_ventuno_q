#!/bin/sh
#
# Prepares the stock Ubuntu image on a VENTUNO Q to install Nerves, then
# reboots into the installer. Run as root by `mix firmware.install`.
#
# Usage: install-prepare.sh <firmware.fw> <sgdisk arguments...>
#
# Ubuntu boots until the ESP is reformatted, which happens only after the
# installer is built.
#
set -eu

fw=$1
shift
work=$(dirname "$fw")
device=/dev/mmcblk0

step() { printf '==> %s\n' "$*"; }

esp=$(findmnt -n -o TARGET "${device}p69" | head -n 1)
[ -n "$esp" ] || { echo "The ESP (${device}p69) is not mounted" >&2; exit 1; }

if ! file -L /bin/busybox 2>/dev/null | grep -q "statically linked" ||
  ! command -v sgdisk >/dev/null || ! command -v mkfs.vfat >/dev/null; then
  step "Installing busybox-static, gdisk and dosfstools"
  apt-get install -y -qq busybox-static gdisk dosfstools >/dev/null
fi

step "Extracting the root filesystem and GRUB from the firmware"
busybox unzip -p "$fw" data/rootfs.img > "$work/rootfs.img"
busybox unzip -p "$fw" data/bootaa64.efi > "$work/bootaa64.efi"
mkdir -p "$work/rootfs"
mount -o loop,ro "$work/rootfs.img" "$work/rootfs"

step "Building the installer"
rm -rf "$work/initramfs"
mkdir -p "$work/initramfs/bin"
cp /bin/busybox "$work/initramfs/bin/busybox"
cp "$work/installer-init" "$work/initramfs/init"
chmod 755 "$work/initramfs/init"
cp "$fw" "$work/initramfs/install.fw"
(cd "$work/initramfs" && find . | cpio -o -H newc --quiet | gzip -1) > "$work/initrd.gz"

# fwup writes FAT filesystems with 512-byte sectors only; Qualcomm formats
# the ESP with 4096-byte ones. Reformat it, keeping the files UEFI stores there.
step "Reformatting the ESP"
mkdir -p "$work/esp-keep"
for f in Persisted_Capsules.bin VolatileVars.bin; do
  if [ -f "$esp/$f" ]; then cp -p "$esp/$f" "$work/esp-keep/"; fi
done
rm -rf "$esp/nerves-install"
umount "$esp"
mkfs.vfat -F 32 -S 512 -n NERVES-ESP "${device}p69" >/dev/null
mount -t vfat "${device}p69" "$esp"
cp -p "$work/esp-keep/"* "$esp/" 2>/dev/null || true
mkdir -p "$esp/EFI/BOOT" "$esp/EFI/ubuntu" "$esp/nerves-install"
cp "$work/rootfs/boot/Image" "$work/rootfs/boot/monaco-arduino-monza.dtb" "$esp/nerves-install/"
umount "$work/rootfs"

free=$(df -P -B1 "$esp" | awk 'NR == 2 { print $4 }')
need=$(stat -c %s "$work/initrd.gz")
if [ "$need" -gt "$free" ]; then
  echo "The ESP has $free bytes free; the installer needs $need" >&2
  exit 1
fi
cp "$work/initrd.gz" "$esp/nerves-install/initrd.gz"
sync

step "Writing the Nerves partition table"
sgdisk "$@"

step "Installing GRUB with the installer entry"
cat > "$esp/EFI/BOOT/grub.cfg" <<'GRUB'
set timeout=0
linux /nerves-install/Image console=ttyMSM0,115200n8 rdinit=/init clk_ignore_unused pd_ignore_unused
initrd /nerves-install/initrd.gz
devicetree /nerves-install/monaco-arduino-monza.dtb
boot
GRUB
cp "$work/bootaa64.efi" "$esp/EFI/BOOT/BOOTAA64.EFI"
cp "$work/bootaa64.efi" "$esp/EFI/ubuntu/shimaa64.efi"
sync

step "Rebooting into the installer"
systemctl reboot
