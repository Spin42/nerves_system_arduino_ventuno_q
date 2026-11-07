#!/usr/bin/env bash
#
# Fetches Qualcomm's AI Runtime (QAIRT) and writes the parts the VENTUNO Q
# needs to run QNN models on its Hexagon NPU into a firmware rootfs overlay:
#
#   <overlay-dir>/opt/qairt/bin                       qnn-net-run, ...
#   <overlay-dir>/opt/qairt/lib                       aarch64 QNN libraries
#   <overlay-dir>/opt/qairt/lib/hexagon-v75/unsigned  CDSP-side libraries
#
# The runtime is under Qualcomm's licence (opt/qairt/LICENSE.pdf), which
# downloading it accepts. It is not part of the system's release: point a
# firmware project's rootfs_overlay at <overlay-dir> to put it in the image.
#
# Usage: fetch-qairt.sh <overlay-dir>
#
# QAIRT_ZIP=<path> uses an already downloaded SDK archive instead.
#
set -euo pipefail

version=2.50.0.260828
sha256=a346ea0e2c8631b46d57261a4969994cd9cc34124a8355bbc7b08b2c8bd859a5
url="https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/$version/v$version.zip"
target=aarch64-oe-linux-gcc11.2

bins="qnn-net-run qnn-context-binary-generator qnn-platform-validator"
libs="libQnnHtp.so libQnnHtpV75Stub.so libQnnHtpPrepare.so libQnnSystem.so
  libQnnHtpNetRunExtensions.so libQnnCpu.so libQnnHtpV75CalculatorStub.so"
dsp_libs="libQnnHtpV75.so libQnnHtpV75Skel.so libQnnSystem.so
  libQnnHtpNetRunExtensions.so libCalculator_skel.so"
notices="LICENSE.pdf NOTICE.txt QNN_NOTICE.txt"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <overlay-dir>" >&2
  exit 1
fi
out="$1/opt/qairt"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/nerves_system_arduino_ventuno_q"
zip="${QAIRT_ZIP:-$cache/qairt-$version.zip}"

if [ ! -f "$zip" ]; then
  mkdir -p "$(dirname "$zip")"
  echo "Downloading QAIRT $version (2.6 GB)"
  curl -fL --retry 3 -o "$zip.part" "$url"
  mv "$zip.part" "$zip"
fi

echo "$sha256  $zip" | sha256sum -c --quiet

prefix="qairt/$version"
members=()
for f in $bins; do members+=("$prefix/bin/$target/$f"); done
for f in $libs; do members+=("$prefix/lib/$target/$f"); done
for f in $dsp_libs; do members+=("$prefix/lib/hexagon-v75/unsigned/$f"); done
for f in $notices; do members+=("$prefix/$f"); done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q -d "$work" "$zip" "${members[@]}"

rm -rf "$out"
mkdir -p "$out/bin" "$out/lib/hexagon-v75/unsigned"
for f in $bins; do install -m 0755 "$work/$prefix/bin/$target/$f" "$out/bin/"; done
for f in $libs; do install -m 0644 "$work/$prefix/lib/$target/$f" "$out/lib/"; done
for f in $dsp_libs; do
  install -m 0644 "$work/$prefix/lib/hexagon-v75/unsigned/$f" "$out/lib/hexagon-v75/unsigned/"
done
for f in $notices; do install -m 0644 "$work/$prefix/$f" "$out/"; done

echo "QAIRT $version runtime written to $out ($(du -sh "$out" | cut -f1))"
