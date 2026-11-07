#!/usr/bin/env bash
# The `sh -c` bodies are expanded by the child shell.
# shellcheck disable=SC2016
#
# Records how Arduino's stock image boots and uses the VENTUNO Q: partitions,
# EFI boot entries, device tree, CPUs, drivers, firmware and DSP files,
# cameras and network. Run as root on the stock image; it writes one tarball
# to the current directory and changes nothing on the board.
#
# Usage: sudo ./survey-stock-image.sh
#
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

name="ventuno-q-survey-$(date +%Y%m%d-%H%M%S)"
out="$(mktemp -d)/$name"
mkdir -p "$out"

# Runs a command, saving its output (or why it failed) under a file name.
capture() {
  local file="$1"
  shift
  {
    echo "\$ $*"
    "$@" 2>&1 || echo "(exit $?)"
  } >"$out/$file.txt"
}

have() { command -v "$1" >/dev/null 2>&1; }

capture uname uname -a
capture os-release cat /etc/os-release
capture cmdline cat /proc/cmdline
capture cpuinfo cat /proc/cpuinfo
capture meminfo cat /proc/meminfo
capture iomem cat /proc/iomem
capture lsmod lsmod
capture dmesg dmesg
capture mounts cat /proc/mounts
capture lsblk lsblk -b -o NAME,MAJ:MIN,SIZE,TYPE,FSTYPE,PARTLABEL,PARTUUID,PARTTYPE,MOUNTPOINTS

for disk in /dev/mmcblk[0-9] /dev/nvme[0-9]n[0-9] /dev/sd[a-z]; do
  [ -b "$disk" ] || continue
  base="$(basename "$disk")"
  capture "gpt-$base" sgdisk -p "$disk"
  capture "gpt-$base-sfdisk" sfdisk --dump "$disk"
done

for hwpart in /dev/mmcblk[0-9]boot[0-9]; do
  [ -b "$hwpart" ] || continue
  capture "size-$(basename "$hwpart")" blockdev --getsize64 "$hwpart"
done

if have efibootmgr; then
  capture efibootmgr efibootmgr -v
fi
capture efivars ls -la /sys/firmware/efi/efivars

esp="$(findmnt -n -o TARGET -t vfat | head -n 1)"
if [ -n "$esp" ]; then
  capture esp-tree find "$esp" -type f -exec ls -la {} +
  for config in "$esp"/loader/loader.conf "$esp"/loader/entries/*.conf "$esp"/EFI/*/grub.cfg; do
    [ -f "$config" ] || continue
    capture "esp-$(echo "${config#"$esp"/}" | tr '/' '_')" cat "$config"
  done
fi

cp /sys/firmware/fdt "$out/fdt.dtb" 2>/dev/null
capture dt-compatible tr '\0' '\n' </proc/device-tree/compatible
capture dt-model tr '\0' '\n' </proc/device-tree/model

capture remoteproc sh -c 'for r in /sys/class/remoteproc/*; do echo "$r $(cat "$r"/name) $(cat "$r"/state) $(cat "$r"/firmware 2>/dev/null)"; done'
capture fastrpc-devices sh -c 'ls -la /dev/fastrpc* /dev/dri /dev/video* /dev/media* /dev/v4l-subdev* 2>&1'

capture firmware-files sh -c 'find /lib/firmware/qcom /lib/firmware/qca /lib/firmware/ath11k -type f -printf "%s %p\n" 2>/dev/null | sort -k2'
capture firmware-sha256 sh -c 'find /lib/firmware/qcom -type f -exec sha256sum {} + 2>/dev/null | sort -k2'
capture dsp-files sh -c 'find /usr/lib/dsp /usr/share/qcom /usr/lib/rfsa /dsp -type f -printf "%s %p\n" 2>/dev/null | sort -k2'
capture qairt-files sh -c 'find / -xdev \( -name "libQnn*.so" -o -name "libcdsprpc.so*" -o -name "*Skel.so" \) -printf "%s %p\n" 2>/dev/null | sort -k2'

if have media-ctl; then
  for media in /dev/media*; do
    [ -e "$media" ] || continue
    capture "media-ctl-$(basename "$media")" media-ctl -p -d "$media"
  done
fi
if have v4l2-ctl; then
  capture v4l2-devices v4l2-ctl --list-devices
fi

capture ip-link ip -d link
capture ethtool-driver sh -c 'for i in /sys/class/net/*; do n=$(basename "$i"); echo "$n: $(readlink -f "$i"/device/driver 2>/dev/null)"; done'
capture usb-devices sh -c 'lsusb -t 2>&1; lsusb 2>&1'
capture i2c-buses sh -c 'ls -la /sys/bus/i2c/devices/'
capture packages sh -c 'dpkg -l 2>/dev/null | grep -iE "qcom|qualcomm|arduino|fastrpc|qnn|qairt|hexagon|mesa|camx|linux-image|firmware"'

tar -C "$(dirname "$out")" -czf "$PWD/$name.tar.gz" "$name"
rm -rf "$(dirname "$out")"
echo "Wrote $PWD/$name.tar.gz"
