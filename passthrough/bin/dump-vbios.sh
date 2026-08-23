#!/bin/bash
# Dump the discrete GPU's vBIOS to a ROM image usable by QEMU/OVMF.
#
# Must be run while booted on the NORMAL Ubuntu entry — once the card is bound
# to vfio-pci the ROM is no longer readable through sysfs.
set -euo pipefail

OUT="${1:-$HOME/.local/share/vfio-assets/gpu.rom}"

GPU_ADDR=$(lspci -Dnn | awk '/VGA compatible controller.*NVIDIA|3D controller.*NVIDIA/ {print $1; exit}')
if [ -z "$GPU_ADDR" ]; then
    echo "No NVIDIA GPU found." >&2
    exit 1
fi
echo "GPU: $GPU_ADDR  $(lspci -s "${GPU_ADDR#0000:}" | cut -d: -f3-)"

ROM="/sys/bus/pci/devices/$GPU_ADDR/rom"
if [ ! -e "$ROM" ]; then
    echo "No ROM sysfs node at $ROM — the card does not expose a shadow BIOS." >&2
    echo "Use NVFlash from Windows instead (see passthrough/assets/README.md)." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

# The ROM node reads as empty until explicitly enabled.
echo 1 | sudo tee "$ROM" >/dev/null
trap 'echo 0 | sudo tee "$ROM" >/dev/null 2>&1 || true' EXIT
sudo cat "$ROM" > "$OUT"

if [ ! -s "$OUT" ]; then
    echo "Dump was empty. The nvidia driver is probably holding the card." >&2
    echo "Try again after 'sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia'," >&2
    echo "from a text console, or dump it from Windows with NVFlash." >&2
    rm -f "$OUT"
    exit 1
fi

echo "Wrote $OUT ($(stat -c%s "$OUT") bytes)"
file "$OUT"
echo
echo "Install it with:  sudo install -m0644 '$OUT' /usr/share/qemu/gpu.rom"
