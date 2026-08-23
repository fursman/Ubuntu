#!/bin/bash
set -euo pipefail

# ============================================================================
# Single-GPU VFIO Passthrough + Looking Glass + Windows VM
#
# Reproduces the gaming/Windows setup on a Razer Blade Pro 17 (RZ09-0368):
# an RTX 3080 Mobile handed to a Windows guest at boot via a dedicated GRUB
# entry, with the guest's framebuffer piped back to the Linux desktop over
# shared memory by Looking Glass.
#
# This is DELIBERATELY SEPARATE from setup.sh. setup.sh is the portable
# desktop; this script is hardware-specific and reboot-affecting.
#
#   ./gpu-passthrough.sh              full install
#   ./gpu-passthrough.sh --check      preflight only, change nothing
#   ./gpu-passthrough.sh --no-vm      host plumbing only, skip VM definition
# ============================================================================

BOLD='\033[1m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PT="$SCRIPT_DIR/passthrough"

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[  OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }
step()    { echo -e "\n${CYAN}${BOLD}-- $1 --${NC}"; }
die()     { error "$1"; exit 1; }

CHECK_ONLY=0
SKIP_VM=0
for arg in "$@"; do
    case "$arg" in
        --check)  CHECK_ONLY=1 ;;
        --no-vm)  SKIP_VM=1 ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *) die "Unknown option: $arg" ;;
    esac
done

echo -e "${BOLD}${CYAN}"
echo "  V F I O   P A S S T H R O U G H"
echo -e "${NC}"
echo -e "${BOLD}  Single-GPU passthrough + Looking Glass${NC}\n"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
step "Preflight"

grep -qE 'vmx|svm' /proc/cpuinfo \
    || die "CPU virtualisation (VT-x/AMD-V) not available. Enable it in firmware."
success "CPU virtualisation extensions present"

# IOMMU must already be on for group enumeration to mean anything.
IOMMU_ON=0
if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    IOMMU_ON=1
    success "IOMMU active ($(ls /sys/kernel/iommu_groups | wc -l) groups)"
else
    warn "IOMMU not active yet — this script will enable it; groups verify after reboot"
fi

CPU_VENDOR=$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)
case "$CPU_VENDOR" in
    GenuineIntel) IOMMU_FLAG="intel_iommu=on" ;;
    AuthenticAMD) IOMMU_FLAG="amd_iommu=on"   ;;
    *) die "Unrecognised CPU vendor: $CPU_VENDOR" ;;
esac
info "IOMMU kernel flag: $IOMMU_FLAG"

# Discrete GPU + its HDMI audio function are passed together; they share a
# PCI function group and the guest driver wants both.
GPU_ADDR=$(lspci -Dnn | awk '/VGA compatible controller.*NVIDIA|3D controller.*NVIDIA/ {print $1; exit}')
[ -n "$GPU_ADDR" ] || die "No discrete NVIDIA GPU found."
GPU_SLOT="${GPU_ADDR%.*}"
# `lspci -Dn` gives bare numeric IDs: "0000:01:00.0 0300: 10de:249c (rev a1)"
GPU_ID=$(lspci -Dn -s "$GPU_ADDR" | awk '{print $3}')
AUDIO_ADDR=$(lspci -Dnn | awk -v s="$GPU_SLOT" '$0 ~ "^"s"\\.[0-9]" && /Audio device/ {print $1; exit}')
if [ -n "$AUDIO_ADDR" ]; then
    AUDIO_ID=$(lspci -Dn -s "$AUDIO_ADDR" | awk '{print $3}')
    VFIO_IDS="$GPU_ID,$AUDIO_ID"
else
    warn "No HDMI audio function alongside the GPU — passing video only"
    VFIO_IDS="$GPU_ID"
fi
success "GPU  $GPU_ADDR  [$GPU_ID]"
[ -n "$AUDIO_ADDR" ] && success "HDMI audio  $AUDIO_ADDR  [$AUDIO_ID]"
info "vfio-pci.ids=$VFIO_IDS"

# The GPU must not share an IOMMU group with anything the host needs.
if [ "$IOMMU_ON" = 1 ]; then
    GRP=$(basename "$(readlink -f "/sys/bus/pci/devices/$GPU_ADDR/iommu_group")")
    info "GPU is in IOMMU group $GRP:"
    for d in /sys/kernel/iommu_groups/$GRP/devices/*; do
        dev=$(basename "$d")
        echo "        $(lspci -nns "${dev#0000:}" 2>/dev/null | sed 's/^/  /')"
    done
    # A stray endpoint in the group means the host would lose that device too.
    STRAY=0
    for d in /sys/kernel/iommu_groups/$GRP/devices/*; do
        dev=$(basename "$d")
        if ! lspci -nns "${dev#0000:}" 2>/dev/null | grep -qiE 'nvidia|PCI bridge'; then
            STRAY=$((STRAY + 1))
        fi
    done
    if [ "$STRAY" -gt 0 ]; then
        warn "Group $GRP contains non-NVIDIA endpoints — passthrough may need ACS override"
    else
        success "IOMMU group is clean (GPU + audio + root port only)"
    fi
fi

# The VM claims a whole physical disk. Identify it rather than guessing.
VM_DISK=""
for d in /dev/nvme*n1 /dev/sd?; do
    [ -b "$d" ] || continue
    # A Windows disk: GPT with an EFI System Partition and a Microsoft reserved part
    if sudo blkid -o value -s PARTLABEL "${d}"* 2>/dev/null | grep -qi 'microsoft reserved' \
       || sudo fdisk -l "$d" 2>/dev/null | grep -q 'Microsoft reserved'; then
        # Never offer the disk the host root lives on
        if ! lsblk -no MOUNTPOINT "$d" 2>/dev/null | grep -qE '^/$|^/boot'; then
            VM_DISK="$d"; break
        fi
    fi
done
if [ -n "$VM_DISK" ]; then
    success "Windows VM disk detected: $VM_DISK ($(lsblk -dno SIZE "$VM_DISK"))"
else
    warn "No Windows disk auto-detected — edit the disk <source dev=...> after import"
fi

if [ "$CHECK_ONLY" = 1 ]; then
    echo; success "Preflight complete (--check: nothing was changed)"; exit 0
fi

# ---------------------------------------------------------------------------
step "1/9 - Packages"
# ---------------------------------------------------------------------------
sudo apt update
sudo apt install -y \
    qemu-system-x86 qemu-utils ovmf \
    libvirt-daemon-system libvirt-clients virt-manager virt-viewer bridge-utils \
    dkms build-essential cmake pkg-config acpica-tools \
    libegl-dev libgl-dev libgles-dev libfontconfig-dev libgmp-dev nettle-dev \
    libspice-protocol-dev binutils-dev libfdt-dev \
    libx11-dev libxfixes-dev libxi-dev libxinerama-dev libxss-dev \
    libxkbcommon-dev libwayland-dev wayland-protocols libdecor-0-dev \
    libpipewire-0.3-dev libsamplerate0-dev libpulse-dev
success "Virtualisation stack + Looking Glass build dependencies installed"

for grp in libvirt kvm; do
    if id -nG "$USER" | grep -qw "$grp"; then
        info "$USER already in $grp"
    else
        sudo usermod -aG "$grp" "$USER"
        info "Added $USER to $grp (re-login required)"
    fi
done

sudo systemctl enable --now libvirtd.socket
sudo virsh net-autostart default 2>/dev/null || true
sudo virsh net-start default 2>/dev/null || true

# ---------------------------------------------------------------------------
step "2/9 - IOMMU kernel flag"
# ---------------------------------------------------------------------------
# Note this goes on the DEFAULT cmdline: IOMMU is needed on every boot, whereas
# the vfio-pci binding is only on the dedicated passthrough entry.
if grep -q "$IOMMU_FLAG" /etc/default/grub; then
    info "$IOMMU_FLAG already in GRUB_CMDLINE_LINUX_DEFAULT"
else
    sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%s)
    sudo sed -i "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"/\1 $IOMMU_FLAG\"/" /etc/default/grub
    success "Added $IOMMU_FLAG to GRUB_CMDLINE_LINUX_DEFAULT"
fi

# ---------------------------------------------------------------------------
step "3/9 - Dedicated 'GPU Passthrough' boot entry"
# ---------------------------------------------------------------------------
# The whole design rests on this: the host has ONE GPU worth passing, so the
# choice of who owns it is made at boot. The normal entry loads `nvidia` and
# you get CUDA + an NVIDIA-accelerated desktop. This entry hands the card to
# vfio-pci before the nvidia driver can claim it, and the desktop falls back to
# the Intel iGPU. No unbind/rebind scripts, no driver ping-pong.
sudo install -m 0755 "$PT/grub.d/40_gpu-passthrough" /etc/grub.d/40_gpu-passthrough

# Bake in this machine's actual IDs rather than the ones captured at authoring time.
sudo sed -i "s/vfio-pci\.ids=[0-9a-f:,]*/vfio-pci.ids=$VFIO_IDS/" /etc/grub.d/40_gpu-passthrough
success "/etc/grub.d/40_gpu-passthrough installed (vfio-pci.ids=$VFIO_IDS)"

# ---------------------------------------------------------------------------
step "4/9 - vfio-pci module ordering"
# ---------------------------------------------------------------------------
# Belt and braces for the boot entry above: even if nvidia is pulled in early
# by the initramfs, these softdeps force vfio-pci to load first so it wins the
# race for the device.
sudo install -m 0644 "$PT/modprobe.d/vfio.conf" /etc/modprobe.d/vfio.conf
success "/etc/modprobe.d/vfio.conf installed"

# ---------------------------------------------------------------------------
step "5/9 - Hugepages"
# ---------------------------------------------------------------------------
# 8192 x 2 MiB = 16 GiB, matching the guest's <memory> exactly. Preallocating
# as hugepages removes TLB pressure and stops the guest's RAM from being
# swapped or fragmented by the host. The VM is also <locked/>.
sudo install -m 0644 "$PT/sysctl.d/99-hugepages.conf" /etc/sysctl.d/99-hugepages.conf
sudo sysctl --system >/dev/null
HP=$(awk '/HugePages_Total/{print $2}' /proc/meminfo)
if [ "$HP" -ge 8192 ]; then
    success "Hugepages reserved: $HP x 2 MiB = $((HP*2/1024)) GiB"
else
    warn "Only $HP hugepages allocated (wanted 8192) — memory too fragmented; reboot to fix"
fi

# ---------------------------------------------------------------------------
step "6/9 - kvmfr kernel module (Looking Glass shared framebuffer)"
# ---------------------------------------------------------------------------
# kvmfr exposes /dev/kvmfr0, a chunk of host memory the guest writes frames
# into directly. This beats a plain ivshmem file: no page-cache round trip,
# and the client can mmap it straight into the GPU upload path.
LG_VERSION="${LG_VERSION:-B7}"
LG_SRC="/usr/src/looking-glass-$LG_VERSION"

if [ ! -d "$LG_SRC" ]; then
    info "Fetching Looking Glass $LG_VERSION source..."
    TMP=$(mktemp -d)
    curl -fsSL "https://looking-glass.io/artifact/$LG_VERSION/source" -o "$TMP/lg.tar.gz" \
        || die "Could not download Looking Glass $LG_VERSION source"
    sudo mkdir -p "$LG_SRC"
    sudo tar -xf "$TMP/lg.tar.gz" -C "$LG_SRC" --strip-components=1
    rm -rf "$TMP"
fi
success "Looking Glass source at $LG_SRC"

KVMFR_VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$LG_SRC/module/dkms.conf" 2>/dev/null || echo "")
if [ -z "$KVMFR_VER" ]; then
    warn "Could not read kvmfr version from dkms.conf — skipping module build"
else
    if dkms status 2>/dev/null | grep -q "^kvmfr/$KVMFR_VER.*$(uname -r).*installed"; then
        info "kvmfr $KVMFR_VER already built for $(uname -r)"
    else
        sudo rm -rf "/usr/src/kvmfr-$KVMFR_VER"
        sudo cp -a "$LG_SRC/module" "/usr/src/kvmfr-$KVMFR_VER"
        sudo dkms install "kvmfr/$KVMFR_VER" --force
        success "kvmfr $KVMFR_VER built and installed via DKMS"
    fi
fi

# static_size_mb=128 sizes the shared buffer. Rule of thumb for Looking Glass:
#   width * height * 4 bytes * 2 frames, rounded up to a power of two.
#   3840x2160x4x2 = 63 MiB -> 64; 128 leaves room for higher refresh buffering.
sudo install -m 0644 "$PT/modprobe.d/kvmfr.conf"      /etc/modprobe.d/kvmfr.conf
sudo install -m 0644 "$PT/modules-load.d/kvmfr.conf"  /etc/modules-load.d/kvmfr.conf
sudo install -m 0644 "$PT/udev/99-kvmfr.rules"        /etc/udev/rules.d/99-kvmfr.rules
# The udev rule hands /dev/kvmfr0 to the desktop user; without it the client
# runs as root or not at all.
sudo sed -i "s/OWNER=\"[^\"]*\"/OWNER=\"$USER\"/" /etc/udev/rules.d/99-kvmfr.rules
sudo udevadm control --reload-rules
sudo modprobe kvmfr 2>/dev/null || warn "kvmfr will load on next boot"
success "kvmfr configured (128 MiB static buffer, owned by $USER)"

# ---------------------------------------------------------------------------
step "7/9 - Looking Glass client"
# ---------------------------------------------------------------------------
if command -v looking-glass-client &>/dev/null \
   && looking-glass-client --version 2>&1 | grep -q "($LG_VERSION)"; then
    info "looking-glass-client $LG_VERSION already installed"
else
    info "Building looking-glass-client $LG_VERSION (this takes a few minutes)..."
    sudo rm -rf "$LG_SRC/client/build"
    sudo mkdir -p "$LG_SRC/client/build"
    ( cd "$LG_SRC/client/build" \
      && sudo cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_WAYLAND=ON -DENABLE_X11=ON .. \
      && sudo make -j"$(nproc)" \
      && sudo make install )
    success "looking-glass-client installed to /usr/local/bin"
fi

# Sensible defaults so the client is usable without command-line flags.
mkdir -p "$HOME/.config/looking-glass"
if [ ! -f "$HOME/.config/looking-glass/client.ini" ]; then
    cat > "$HOME/.config/looking-glass/client.ini" <<'LGEOF'
[app]
shmFile=/dev/kvmfr0
allowDMA=yes

[win]
title=Windows
fullScreen=no
autoResize=yes
quickSplash=yes
uiFont=JetBrainsMono Nerd Font

[input]
; Ctrl+Ctrl releases the cursor. rawMouse keeps 1:1 motion for games.
escapeKey=KEY_RIGHTCTRL
rawMouse=yes
autoCapture=yes

[spice]
enable=yes
audio=yes
LGEOF
    success "~/.config/looking-glass/client.ini written"
else
    info "Looking Glass client.ini already present, leaving it alone"
fi

# ---------------------------------------------------------------------------
step "8/9 - Guest firmware assets"
# ---------------------------------------------------------------------------
sudo mkdir -p /usr/share/qemu

# --- vBIOS ---------------------------------------------------------------
# Laptop GPUs have no VGA BIOS the guest can shadow, so OVMF must be handed the
# ROM explicitly or the guest black-screens with Code 43.
ROM_FOUND=""
for cand in "$HOME/.local/share/vfio-assets/gpu.rom" \
            "/usr/share/qemu/gpu.rom" \
            "$PT/assets/gpu.rom"; do
    [ -s "$cand" ] && { ROM_FOUND="$cand"; break; }
done
if [ -n "$ROM_FOUND" ]; then
    [ "$ROM_FOUND" = "/usr/share/qemu/gpu.rom" ] \
        || sudo install -m 0644 "$ROM_FOUND" /usr/share/qemu/gpu.rom
    success "vBIOS installed from $ROM_FOUND"
else
    warn "No gpu.rom found — dumping one from the running card"
    if "$PT/bin/dump-vbios.sh"; then
        sudo install -m 0644 "$HOME/.local/share/vfio-assets/gpu.rom" /usr/share/qemu/gpu.rom
        success "vBIOS dumped and installed"
    else
        warn "vBIOS dump failed. See passthrough/assets/README.md before starting the VM."
    fi
fi

# --- Fake battery --------------------------------------------------------
# NVIDIA's driver refuses to initialise a *mobile* GPU inside a VM that looks
# like a desktop: no battery means "this isn't a laptop" means Code 43. This
# SSDT injects a fixed 100%-charged battery so the guest driver is satisfied.
# Recompiled from source so the table is auditable rather than an opaque blob.
if [ -f "$PT/acpi/ssdt-battery.asl" ] && command -v iasl &>/dev/null; then
    TMP=$(mktemp -d)
    cp "$PT/acpi/ssdt-battery.asl" "$TMP/ssdt-battery.asl"
    ( cd "$TMP" && iasl -ve ssdt-battery.asl >/dev/null 2>&1 ) || true
    if [ -s "$TMP/ssdt-battery.aml" ]; then
        sudo install -m 0644 "$TMP/ssdt-battery.aml" /usr/share/qemu/ssdt-battery.aml
        success "ssdt-battery.aml recompiled from ASL source"
    else
        sudo install -m 0644 "$PT/acpi/ssdt-battery.aml" /usr/share/qemu/ssdt-battery.aml
        warn "iasl recompile failed — installed the prebuilt .aml instead"
    fi
    rm -rf "$TMP"
else
    sudo install -m 0644 "$PT/acpi/ssdt-battery.aml" /usr/share/qemu/ssdt-battery.aml
    success "ssdt-battery.aml installed (prebuilt)"
fi

# ---------------------------------------------------------------------------
step "9/9 - Host tuning, controller passthrough, and the VM"
# ---------------------------------------------------------------------------
# Pin all cores to the performance governor. With 8 of 16 threads handed to the
# guest, letting the host race to idle causes audible stutter in the VM.
sudo install -m 0644 "$PT/udev/50-cpu-performance.rules"    /etc/udev/rules.d/50-cpu-performance.rules
# The xHCI controller spuriously wakes this laptop from suspend; mask it.
sudo install -m 0644 "$PT/udev/90-disable-usb-wakeup.rules" /etc/udev/rules.d/90-disable-usb-wakeup.rules

# Hot-plug the 8BitDo pad straight into the guest when it connects, so the
# controller "just works" without opening virt-manager.
sudo install -m 0755 "$PT/bin/8bitdo-passthrough" /usr/local/bin/8bitdo-passthrough
sudo install -m 0644 "$PT/udev/99-8bitdo-passthrough.rules" /etc/udev/rules.d/99-8bitdo-passthrough.rules
sudo udevadm control --reload-rules
success "udev rules installed (cpu governor, usb wakeup, 8BitDo auto-attach)"

# Day-to-day lifecycle helpers. lg-start refuses to run and says why if the
# GPU is not actually bound to vfio-pci, which is the mistake you make after
# forgetting to pick the passthrough entry at boot.
mkdir -p "$HOME/.local/bin"
install -m 0755 "$PT/bin/lg-start" "$HOME/.local/bin/lg-start"
install -m 0755 "$PT/bin/lg-stop"  "$HOME/.local/bin/lg-stop"
success "lg-start / lg-stop installed to ~/.local/bin"

if [ "$SKIP_VM" = 1 ]; then
    info "--no-vm given, skipping domain definition"
elif sudo virsh dominfo win10-lg &>/dev/null; then
    info "Domain 'win10-lg' already defined — not overwriting"
    info "To re-import:  sudo virsh undefine --nvram win10-lg && ./gpu-passthrough.sh"
else
    TMPXML=$(mktemp)
    cp "$PT/vm/win10-lg.xml" "$TMPXML"

    # Rewrite the captured host's values to this machine's.
    if [ -n "$VM_DISK" ]; then
        sed -i "s|<source dev='/dev/[^']*'/>|<source dev='$VM_DISK'/>|" "$TMPXML"
        info "VM disk set to $VM_DISK"
    fi
    # Point the two <hostdev> sources at this machine's actual GPU functions.
    # 0000:01:00.0 -> domain 0x0000 bus 0x01 slot 0x00 function 0x0
    IFS=':.' read -r H_DOM H_BUS H_SLOT H_FN <<<"$GPU_ADDR"
    python3 - "$TMPXML" "$H_DOM" "$H_BUS" "$H_SLOT" <<'PYEOF'
import re, sys
path, dom, bus, slot = sys.argv[1:5]
xml = open(path).read()
# Only <hostdev><source> addresses describe host devices; leave guest-side
# <address> elements (which assign PCI slots inside the VM) untouched.
def fix(m):
    fn = re.search(r"function='(0x[0-9a-f]+)'", m.group(0)).group(1)
    return ("<source>\n        <address domain='0x%s' bus='0x%s' slot='0x%s' function='%s'/>\n      </source>"
            % (dom, bus, slot, fn))
xml = re.sub(r"<source>\s*<address domain='0x[0-9a-f]+' bus='0x[0-9a-f]+' "
             r"slot='0x[0-9a-f]+' function='0x[0-9a-f]+'/>\s*</source>", fix, xml)
open(path, 'w').write(xml)
PYEOF
    info "hostdev sources repointed to $GPU_ADDR"

    # A fresh domain needs a fresh UUID and MAC or libvirt will collide.
    NEWUUID=$(uuidgen)
    sed -i "s|<uuid>[^<]*</uuid>|<uuid>$NEWUUID</uuid>|" "$TMPXML"
    sed -i "s|uuid=[0-9a-f-]\{36\}|uuid=$NEWUUID|" "$TMPXML"
    NEWMAC=$(printf '52:54:00:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    sed -i "s|<mac address='[^']*'/>|<mac address='$NEWMAC'/>|" "$TMPXML"

    if sudo virsh define "$TMPXML"; then
        success "Domain 'win10-lg' defined (uuid $NEWUUID)"
    else
        error "virsh define failed — inspect $TMPXML"
        cp "$TMPXML" /tmp/win10-lg-failed.xml
        warn "Copy left at /tmp/win10-lg-failed.xml"
    fi
    rm -f "$TMPXML"
fi

# ---------------------------------------------------------------------------
sudo update-grub
# ---------------------------------------------------------------------------

echo ""
echo -e "${GREEN}${BOLD}==========================================${NC}"
echo -e "${GREEN}${BOLD}  GPU passthrough configured               ${NC}"
echo -e "${GREEN}${BOLD}==========================================${NC}"
echo ""
echo -e "  ${BOLD}How this works day to day:${NC}"
echo ""
echo -e "    Normal boot        NVIDIA drives the Linux desktop, CUDA works,"
echo -e "                       the VM will NOT start with the GPU attached."
echo ""
echo -e "    ${CYAN}Ubuntu (GPU Passthrough)${NC}"
echo -e "                       GPU is bound to vfio-pci at boot. The desktop"
echo -e "                       runs on Intel graphics. Start the VM, then run"
echo -e "                       ${BOLD}looking-glass-client${NC} to see the guest."
echo ""
echo -e "  Pick the entry from the GRUB menu at boot (${BOLD}GRUB_TIMEOUT=3${NC})."
echo -e "  Release the Looking Glass cursor with ${BOLD}Right-Ctrl${NC}."
echo ""
echo -e "  ${YELLOW}Reboot required${NC} for hugepages, IOMMU and vfio binding.\n"
