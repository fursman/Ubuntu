# Machine-local binary assets (not tracked in git)

This directory holds binary blobs that are **deliberately excluded from version
control** — see `.gitignore` in the repo root.

## `gpu.rom` — NVIDIA vBIOS image

The Windows VM passes an explicit vBIOS to the guest:

```xml
<rom file='/usr/share/qemu/gpu.rom'/>
```

On a laptop the GPU has no legacy VGA BIOS shadow available to the guest, so
OVMF cannot initialise the card without being handed a ROM image directly.
Without it the guest boots to a black screen and Device Manager reports
Code 43.

This file is a proprietary NVIDIA firmware image. It is **not redistributable**,
so it is not committed to this public repository. `gpu-passthrough.sh` will look
for it in these places, in order:

1. `~/.local/share/vfio-assets/gpu.rom`
2. `/usr/share/qemu/gpu.rom` (already installed)
3. `passthrough/assets/gpu.rom` (this directory)

If none exist the script dumps a fresh one from the running card.

## Re-dumping the vBIOS

Run the helper:

```bash
./passthrough/bin/dump-vbios.sh
```

It reads the ROM through sysfs *before* the GPU is bound to `vfio-pci`, which is
the only window where the card will hand it over. Boot the **normal** Ubuntu
entry (not the GPU Passthrough one) to do this.

If sysfs refuses — some Optimus laptops keep the ROM locked while the `nvidia`
module is loaded — the fallback is to grab it from a Windows install with
[NVFlash](https://www.techpowerup.com/download/nvidia-nvflash/):

```
nvflash64 --save gpu.rom
```

For a mobile GPU the dumped image usually needs no header trimming; desktop
cards sometimes require stripping everything before the `U.\xaa\x55` signature.
Verify with:

```bash
file gpu.rom     # should report: BIOS (ia32) ROM Ext. ... PCI NVIDIA device=0x249c
```
