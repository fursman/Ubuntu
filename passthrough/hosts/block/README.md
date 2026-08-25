# Block -- host-specific passthrough files

Block is a desktop (i9-13900K, UHD 770 iGPU, RTX 4090, LUKS root on LVM, GRUB),
not the Razer Blade the top-level `gpu-passthrough.sh` was written for. These
are the files as installed on it on 2026-08-24. Copy, don't run: the boot UUID,
kernel pin and PCI IDs are Block's.

| file | installs to |
|---|---|
| `40_gpu-passthrough` | `/etc/grub.d/40_gpu-passthrough` (mode 0755), then `update-grub` |
| `vfio.conf` | `/etc/modprobe.d/vfio.conf` |

## Facts the config depends on

- RTX 4090 `01:00.0` = `10de:2684`, its HDMI audio `01:00.1` = `10de:22ba`.
  **IOMMU group 17 is clean** (just those two + the root port) -- no ACS override.
- IOMMU is already active on this board (27 groups) without `intel_iommu=on`;
  the flag is kept for explicitness, `iommu=pt` for host I/O.
- Windows lives natively on the 1.8TB SATA SSD:
  `/dev/disk/by-id/ata-WDC_WDS200T2B0B-00YS70_183797800226` (ESP UUID `503E-E6B7`).
  Pass the **block device**, not the SATA controller (its IOMMU group drags in
  other devices). Boot it on a virtual SATA controller first; Windows already
  has that driver in its boot-critical set. Looking Glass is already installed
  inside that Windows.
- **Never run the VM while the host has any partition of that disk mounted, and
  disable Windows Fast Startup** -- a hibernated NTFS touched from both sides is
  how the filesystem gets corrupted.

## Gotchas found the hard way

- `GRUB_TIMEOUT_STYLE=hidden` + `GRUB_TIMEOUT=0` makes the new entry
  **unreachable**. Block was changed to `menu` / `5`.
- `snd_hda_intel` grabs the GPU's audio function before `vfio-pci` unless the
  softdep in `vfio.conf` is present -- the VM then fails with "group not viable".
- Do **not** put `options vfio-pci ids=...` in modprobe.d: that applies to both
  boot entries and steals the GPU in normal mode. The IDs live only on the
  passthrough entry's kernel command line.
- `kvmfr` (Looking Glass shared-memory module) is not packaged; it needs a DKMS
  build from the Looking Glass tree. Start with the plain `/dev/shm/looking-glass`
  path and add kvmfr once the VM boots.
- `pcie_aspm=off nvme_core.default_ps_max_latency_us=0` are on **both** entries:
  Block's Phison NVMe (`1987:5016`) throws PCIe correctable errors and stalls
  I/O with ASPM on. Unrelated to passthrough, required for the box to be stable.
