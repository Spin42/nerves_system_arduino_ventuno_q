#!/bin/sh

set -e

# Writes a 1024-byte GRUB environment block with the Nerves slot state.
make_grubenv() {
    file=$1
    slot=$2
    validated=$3
    {
        printf '# GRUB Environment Block\n'
        printf 'nerves_slot=%s\nnerves_validated=%s\nnerves_tried=0\n' "$slot" "$validated"
    } > "$file"
    size=$(wc -c < "$file")
    head -c $((1024 - size)) /dev/zero | tr '\0' '#' >> "$file"
}

# grubenv variants that fwup writes to the ESP: a validated slot, or a slot
# that boots once on trial.
make_grubenv "$BINARIES_DIR/grubenv_a_valid" a 1
make_grubenv "$BINARIES_DIR/grubenv_b_valid" b 1
make_grubenv "$BINARIES_DIR/grubenv_a_trial" a 0
make_grubenv "$BINARIES_DIR/grubenv_b_trial" b 0

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p "$TARGET_DIR/usr/share/fwup"
NERVES_SYSTEM="$BASE_DIR" "$HOST_DIR/usr/bin/fwup" -c -f "$NERVES_DEFCONFIG_DIR/fwup-ops.conf" -o "$TARGET_DIR/usr/share/fwup/ops.fw"
ln -sf ops.fw "$TARGET_DIR/usr/share/fwup/revert.fw"

# Copy the fwup includes and the GRUB script to the images dir
cp -rf "$NERVES_DEFCONFIG_DIR/fwup_include" "$BINARIES_DIR"
cp -f "$NERVES_DEFCONFIG_DIR/grub.cfg" "$BINARIES_DIR/grub.cfg"
