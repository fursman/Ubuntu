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


## Found the hard way, 2026-10-11 (first full RTX 4090 + Looking Glass bring-up)

Everything below was discovered bringing the VM up end to end for the first
time. All of it is required; none of it is optional tuning.

- **Resizable BAR must be OFF in firmware.** With ReBAR on, the 4090 exposes its
  whole VRAM as one giant BAR and QEMU/VFIO cannot DMA-map it: the VM dies at
  device init with `vfio: DMA mapping failed, unable to continue`. Off shrinks
  BAR1 to 256 MiB. (Leave Above-4G Decoding ON.)

- **The guest needs `<maxphysaddr mode='passthrough' limit='39'/>`.** This is the
  single most obscure fix. Block's VT-d IOMMU is **39-bit** (`DMAR: Host address
  width 39`, 512 GiB). With host-passthrough CPU, QEMU places the Looking Glass
  kvmfr/ivshmem shared-memory BAR up at ~56 TiB, the IOMMU can't map an address
  that high, `vfio_container_dma_map(... ) = -22` and the VM aborts. Capping the
  guest's physical-address width to 39 forces that window below 512 GiB where the
  IOMMU can map it. It **must** be `mode='passthrough' limit='39'` -- `limit='40'`
  is one bit too high and still fails, and `mode='emulate' bits='39'` does not
  relocate the window at all. AMD is usually 40, Intel usually 39; it is per-CPU.

- **In Windows: turn OFF Memory Integrity (Core Isolation).** Otherwise the guest
  bluescreens `HYPERVISOR_ERROR` (stop code `0x20001`) on cold boot -- it does
  this on bare metal too, so it looks like a VM problem but is not. `bcdedit /set
  hypervisorlaunchtype off` alone is **silently re-enabled** while Memory
  Integrity is on, so the Windows Security GUI toggle is the one that sticks.
  Exposing nested `vmx` to the guest was not sufficient on its own.

- **The whole SATA controller (`00:17.0`, `8086:7ae2`) passes cleanly** and is
  what we actually used -- it is alone in its IOMMU group, so Windows gets its
  real AHCI hardware and boots exactly as on bare metal. (This supersedes the
  older note above about passing only the block device on a virtual controller;
  controller passthrough turned out simpler and needed no boot-critical driver
  juggling.) A one-time bare-metal boot + `chkdsk` + **full** shutdown was needed
  to clear a dirty/transplant NTFS state before it would boot in the VM.

- **`<on_reboot>destroy</on_reboot>` is mandatory.** The 4090 does not reset on a
  guest reboot-in-place: the VM wedges paused with `cont: Resetting the Virtual
  Machine is required`. Turning a guest reboot into a full power-off (then start
  again) resets the card cleanly every time.

- **kvmfr needs two host permissions** beyond building the module: `/dev/kvmfr0`
  in `cgroup_device_acl` in `/etc/libvirt/qemu.conf`, and `/dev/kvmfr0 rw,` in
  `/etc/apparmor.d/local/abstractions/libvirt-qemu` (virt-aa-helper never adds it
  because it is referenced only via `<qemu:commandline>`, not a real device).

- **The Looking Glass host app in Windows does not auto-start.** Set it to run as
  a service / at login, or the client just shows the broken-window logo
  ("waiting for host") until someone logs in and starts it by hand.

- **caps-sudo disarms on every reboot and does not reliably reach an SSH
  session.** Arm it immediately before a privileged step, and expect to re-arm
  after each of the many reboots this work takes.
