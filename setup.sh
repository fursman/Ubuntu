#!/bin/bash
set -euo pipefail

# ============================================================================
# Stock Ubuntu -> Hyprland Desktop
#
# Target: Ubuntu 26.04 LTS (resolute). Works on any release the Hyprland PPA
# publishes for; the codename is resolved at runtime, never hardcoded.
#
#   ./setup.sh                 full run
#   ./setup.sh --configs-only  redeploy dotfiles + theme, install nothing
#   ./setup.sh --no-nvidia     skip the GPU driver step
#
# Hardware-specific VFIO/Looking-Glass/Windows-VM setup lives in a separate
# script: ./gpu-passthrough.sh
# ============================================================================

BOLD='\033[1m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[  OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }
step()    { echo -e "\n${CYAN}${BOLD}-- $1 --${NC}"; }

CONFIGS_ONLY=0
SKIP_NVIDIA=0
for arg in "$@"; do
    case "$arg" in
        --configs-only) CONFIGS_ONLY=1 ;;
        --no-nvidia)    SKIP_NVIDIA=1 ;;
        -h|--help) sed -n '3,16p' "$0"; exit 0 ;;
        *) error "Unknown option: $arg"; exit 1 ;;
    esac
done

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
RELEASE="$(. /etc/os-release && echo "$VERSION_ID")"

echo -e "${BOLD}${CYAN}"
echo "  H Y P R L A N D"
echo -e "${NC}"
echo -e "${BOLD}  Stock Ubuntu -> Hyprland Desktop${NC}"
echo -e "  Detected: Ubuntu $RELEASE ($CODENAME)\n"

# apt-get, not apt: stable CLI, no "unstable interface" warnings in scripts.
APT_GET=(sudo DEBIAN_FRONTEND=noninteractive apt-get -y
         -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Install only what is missing, so re-runs are fast and quiet.
apt_need() {
    local missing=()
    for p in "$@"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed$' \
            || missing+=("$p")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        info "already installed: $*"
    else
        info "installing: ${missing[*]}"
        "${APT_GET[@]}" install "${missing[@]}"
    fi
}

if [ "$CONFIGS_ONLY" = 1 ]; then
    warn "--configs-only: skipping every install step"
fi

# ---------------------------------------------------------------------------
if [ "$CONFIGS_ONLY" = 0 ]; then
step "1/10 - Repositories"
# ---------------------------------------------------------------------------
# The archive carries Hyprland, but a release or two behind. The PPA tracks
# upstream, which matters because the config in this repo uses syntax
# (windowrule v2 `match:`, the `gesture =` form) that older builds reject.
if [ -f "/etc/apt/sources.list.d/cppiber-ubuntu-hyprland-$CODENAME.sources" ]; then
    info "Hyprland PPA already configured for $CODENAME"
elif sudo add-apt-repository -y ppa:cppiber/hyprland 2>/dev/null; then
    success "Hyprland PPA added for $CODENAME"
else
    warn "Hyprland PPA has no $CODENAME series — falling back to the archive"
    warn "If Hyprland is older than 0.55, some window rules in hyprland.conf will warn"
fi

sudo dpkg --configure -a 2>/dev/null || true
sudo apt-get update

step "2/10 - Packages"
# -- Compositor and its immediate surroundings --
apt_need hyprland waybar kitty rofi wlogout gtklock \
         xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
         sway-notification-center swayosd swayidle \
         grim slurp swappy wl-clipboard cliphist wtype wf-recorder

# -- polkit agent --
# Without one, anything that needs authentication (mounting a disk in Thunar,
# GParted, virt-manager) fails silently with no prompt. Stock GNOME ships an
# agent; a bare Hyprland session does not.
if apt-cache show hyprpolkitagent >/dev/null 2>&1; then
    apt_need hyprpolkitagent
    POLKIT_AGENT="/usr/libexec/hyprpolkitagent"
else
    apt_need polkitd-pkla lxpolkit || true
    POLKIT_AGENT="/usr/bin/lxpolkit"
fi

# -- Desktop services and apps --
apt_need thunar thunar-volman tumbler pavucontrol \
         brightnessctl playerctl pamixer \
         gnome-keyring seahorse network-manager-gnome blueman \
         btop fastfetch mpv imagemagick ffmpeg \
         papirus-icon-theme fonts-jetbrains-mono fonts-font-awesome \
         git git-lfs gh curl wget flatpak timeshift

# -- Toolchain (also covers building awww) --
apt_need build-essential pkg-config meson ninja-build cmake \
         python3-dev python3-venv python3-pip \
         libwayland-dev wayland-protocols liblz4-dev scdoc

success "Packages installed"

# Backlight control via brightnessctl/swayosd needs video group membership.
if id -nG "$USER" | grep -qw video; then
    info "$USER already in video group"
else
    sudo usermod -aG video "$USER"
    info "Added $USER to video group (re-login required for backlight keys)"
fi

step "3/10 - Razer hardware support"
# This repo's reference machine is a Razer Blade. openrazer drives the
# per-key RGB and fan control; harmless to skip elsewhere.
if lsusb 2>/dev/null | grep -qi 'Razer' || sudo dmidecode -s system-manufacturer 2>/dev/null | grep -qi razer; then
    apt_need openrazer-meta python3-openrazer
    sudo usermod -aG plugdev "$USER" 2>/dev/null || true
    success "OpenRazer installed"
else
    info "No Razer hardware detected, skipping"
fi

step "4/10 - NVIDIA driver"
if [ "$SKIP_NVIDIA" = 1 ]; then
    info "--no-nvidia given, skipping"
elif ! lspci | grep -qi 'nvidia'; then
    info "No NVIDIA GPU detected, skipping"
else
    # Prefer the DISTRO-SIGNED prebuilt modules over DKMS. They survive
    # Secure Boot, and they do not need rebuilding on every kernel bump —
    # which is what silently breaks a DKMS setup after an unattended upgrade.
    NV_VER=$(ubuntu-drivers devices 2>/dev/null \
             | awk '/recommended/ {print $3}' | grep -oP 'nvidia-driver-\K[0-9]+' | head -1)
    if [ -z "$NV_VER" ]; then
        NV_VER=$(apt-cache search --names-only '^nvidia-driver-[0-9]+-open$' \
                 | grep -oP 'nvidia-driver-\K[0-9]+' | sort -n | tail -1)
    fi

    if [ -z "$NV_VER" ]; then
        warn "Could not determine an NVIDIA driver version — install manually"
    elif nvidia-smi &>/dev/null && [ "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)" = "$NV_VER" ]; then
        info "nvidia-driver-$NV_VER already active"
    else
        info "Installing nvidia-driver-$NV_VER-open (signed prebuilt modules)"
        HWE=$(apt-cache search --names-only "^linux-modules-nvidia-$NV_VER-open-generic-hwe-" \
              | awk '{print $1}' | sort -V | tail -1)
        apt_need "nvidia-driver-$NV_VER-open" ${HWE:+"$HWE"}
        # Pin them manual: if the metapackage is only ever pulled in as a
        # dependency, a later `apt autoremove` will quietly rip the driver out.
        sudo apt-mark manual "nvidia-driver-$NV_VER-open" ${HWE:+"$HWE"} >/dev/null
        success "nvidia-driver-$NV_VER-open installed and pinned"
    fi

    # DRM modeset is mandatory for Wayland on NVIDIA; fbdev gives a working
    # console and avoids a black screen between GRUB and the compositor.
    if [ ! -f /etc/modprobe.d/nvidia-drm.conf ] || ! grep -q 'modeset=1' /etc/modprobe.d/nvidia-drm.conf; then
        echo 'options nvidia-drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf >/dev/null
        sudo update-initramfs -u
        success "nvidia-drm modeset=1 fbdev=1 configured"
    else
        info "nvidia-drm modeset already configured"
    fi
fi

step "5/10 - Node.js 22"
if command -v node &>/dev/null && node -v | grep -q '^v22'; then
    info "Node.js $(node -v) already installed"
else
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    apt_need nodejs
fi
success "Node.js $(node -v 2>/dev/null || echo pending) ready"

step "6/10 - Fonts"
FONT_DIR="$HOME/.local/share/fonts"
if ls "$FONT_DIR"/JetBrainsMonoNerd* &>/dev/null; then
    info "JetBrainsMono Nerd Font already installed"
else
    mkdir -p "$FONT_DIR"
    NERD_VERSION="v3.4.0"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/JetBrainsMono.tar.xz" \
        -o /tmp/JetBrainsMono.tar.xz
    tar -xf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR"
    rm -f /tmp/JetBrainsMono.tar.xz
    fc-cache -f
    success "JetBrainsMono Nerd Font installed"
fi

step "7/10 - GTK theme"
if [ -d "$HOME/.themes/Dracula" ]; then
    info "Dracula GTK theme already present"
else
    git clone --depth 1 https://github.com/dracula/gtk.git "$HOME/.themes/Dracula"
    success "Dracula GTK theme installed"
fi
if [ -d "$HOME/.icons/Dracula" ]; then
    info "Dracula icon theme already present"
else
    git clone --depth 1 https://github.com/m4thewz/dracula-icons.git /tmp/dracula-icons
    mkdir -p "$HOME/.icons/Dracula"
    cp -r /tmp/dracula-icons/* "$HOME/.icons/Dracula/"
    rm -rf /tmp/dracula-icons
    success "Dracula icon theme installed"
fi

fi  # end CONFIGS_ONLY guard

# ---------------------------------------------------------------------------
step "8/10 - Configuration files"
# ---------------------------------------------------------------------------
declare -A CONFIG_MAP=(
    ["configs/hypr/hyprland.conf"]="$HOME/.config/hypr/hyprland.conf"
    ["configs/waybar/config.jsonc"]="$HOME/.config/waybar/config.jsonc"
    ["configs/waybar/style.css"]="$HOME/.config/waybar/style.css"
    ["configs/kitty/kitty.conf"]="$HOME/.config/kitty/kitty.conf"
    ["configs/rofi/config.rasi"]="$HOME/.config/rofi/config.rasi"
    ["configs/mako/config"]="$HOME/.config/mako/config"
    ["configs/wlogout/layout"]="$HOME/.config/wlogout/layout"
    ["configs/wlogout/style.css"]="$HOME/.config/wlogout/style.css"
    ["configs/gtklock/style.css"]="$HOME/.config/gtklock/style.css"
    ["configs/swaync/config.json"]="$HOME/.config/swaync/config.json"
    ["configs/swaync/style.css"]="$HOME/.config/swaync/style.css"
    ["configs/gtk-3.0/settings.ini"]="$HOME/.config/gtk-3.0/settings.ini"
    ["configs/gtk-4.0/settings.ini"]="$HOME/.config/gtk-4.0/settings.ini"
)

for src in "${!CONFIG_MAP[@]}"; do
    dest="${CONFIG_MAP[$src]}"
    mkdir -p "$(dirname "$dest")"
    cp "$SCRIPT_DIR/$src" "$dest"
    info "-> $dest"
done

# The shared palette. GTK CSS has no ~ expansion and no search path, so every
# stylesheet that says `@import "palette.css"` needs a copy next to it.
for d in waybar swaync wlogout gtklock; do
    mkdir -p "$HOME/.config/$d"
    cp "$SCRIPT_DIR/configs/theme/dracula.css" "$HOME/.config/$d/palette.css"
done
info "-> palette.css deployed to waybar, swaync, wlogout, gtklock"

mkdir -p "$HOME/.local/share/rofi/themes"
cp "$SCRIPT_DIR/configs/rofi/spotlight-dark.rasi" "$HOME/.local/share/rofi/themes/spotlight-dark.rasi"
info "-> ~/.local/share/rofi/themes/spotlight-dark.rasi"

# wlogout's CSS references icons by absolute path; GTK will not expand ~.
sed -i "s|/HOME_DIR|$HOME|g" "$HOME/.config/wlogout/style.css"

# -- Machine-local Hyprland environment -------------------------------------
# Kept in its own file so a config redeploy never clobbers GPU-specific tuning.
ENV_LOCAL="$HOME/.config/hypr/env-local.conf"
DRM_CARDS=""
for card in /dev/dri/card*; do
    [ -e "$card" ] || continue
    udevadm info "$card" 2>/dev/null | grep -q "platform-simple-framebuffer" && continue
    DRM_CARDS="${DRM_CARDS:+$DRM_CARDS:}$card"
done

cat > "$ENV_LOCAL" <<EOF
# Auto-generated by setup.sh — machine-specific environment overrides.
# Safe to edit: config redeploys do not overwrite this file's siblings.
# DRM devices detected: $DRM_CARDS
env = WLR_DRM_DEVICES,$DRM_CARDS
EOF

if lspci | grep -qi 'nvidia'; then
    cat >> "$ENV_LOCAL" <<'ENVEOF'

# NVIDIA
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia
ENVEOF
    info "NVIDIA env vars written"
elif lspci | grep -qi 'intel.*graphics'; then
    cat >> "$ENV_LOCAL" <<'ENVEOF'

# Intel
env = LIBVA_DRIVER_NAME,iHD
ENVEOF
    info "Intel env vars written"
fi

cat >> "$ENV_LOCAL" <<'ENVEOF'

# Wayland-native application hints
env = MOZ_ENABLE_WAYLAND,1
env = MOZ_DBUS_REMOTE,1
env = GDK_BACKEND,wayland,x11
env = SDL_VIDEODRIVER,wayland
env = CLUTTER_BACKEND,wayland
env = QT_QPA_PLATFORM,wayland;xcb
env = ELECTRON_OZONE_PLATFORM_HINT,auto
ENVEOF
success "Config files deployed"

# ---------------------------------------------------------------------------
step "9/10 - Helper scripts and session wiring"
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
for script in "$SCRIPT_DIR"/scripts/*; do
    [ -f "$script" ] || continue
    install -m 0755 "$script" "$HOME/.local/bin/$(basename "$script")"
    info "-> ~/.local/bin/$(basename "$script")"
done

# Record which polkit agent to launch, so hyprland.conf can stay generic.
mkdir -p "$HOME/.config/hypr"
if [ -n "${POLKIT_AGENT:-}" ] && [ -x "${POLKIT_AGENT:-}" ]; then
    echo "exec-once = $POLKIT_AGENT" > "$HOME/.config/hypr/polkit-local.conf"
elif [ -x /usr/libexec/hyprpolkitagent ]; then
    echo "exec-once = /usr/libexec/hyprpolkitagent" > "$HOME/.config/hypr/polkit-local.conf"
elif [ -x /usr/bin/lxpolkit ]; then
    echo "exec-once = /usr/bin/lxpolkit" > "$HOME/.config/hypr/polkit-local.conf"
else
    : > "$HOME/.config/hypr/polkit-local.conf"
    warn "No polkit agent found — authentication prompts will not appear"
fi
info "-> ~/.config/hypr/polkit-local.conf"

if [ "$CONFIGS_ONLY" = 0 ]; then
    # swaync owns org.freedesktop.Notifications. mako arrives as a dependency of
    # some Wayland metapackages and will fight it for the bus name.
    systemctl --user mask mako.service 2>/dev/null \
        && info "Masked mako.service (swaync is the notification daemon)" || true
    systemctl --user daemon-reload 2>/dev/null || true
fi
success "Helper scripts installed"

# ---------------------------------------------------------------------------
if [ "$CONFIGS_ONLY" = 0 ]; then
step "10/10 - Wallpaper daemon, assets, and tuning"
# ---------------------------------------------------------------------------
# awww is not packaged anywhere; distro Rust is usually too old to build it.
if command -v rustup &>/dev/null || [ -x "$HOME/.cargo/bin/rustup" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    rustup update stable >/dev/null 2>&1 || true
else
    info "Installing Rust via rustup (needed to build awww)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"
fi

if command -v awww &>/dev/null || [ -x "$HOME/.local/bin/awww" ]; then
    info "awww already installed"
else
    AWWW_DIR=$(mktemp -d)
    if git clone --depth=1 https://codeberg.org/LGFae/awww.git "$AWWW_DIR" 2>/dev/null \
       && [ -f "$AWWW_DIR/Cargo.toml" ]; then
        ( cd "$AWWW_DIR" && cargo build --release )
        install -m 0755 "$AWWW_DIR/target/release/awww"        "$HOME/.local/bin/"
        install -m 0755 "$AWWW_DIR/target/release/awww-daemon" "$HOME/.local/bin/"
        success "awww built and installed"
    else
        warn "awww clone/build failed — wallpaper will fall back to hyprpaper"
    fi
    rm -rf "$AWWW_DIR"
fi
mkdir -p "$HOME/.cache/awww"

# -- Desktop assets --
ASSETS_DIR=$(mktemp -d)
mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/.config/wlogout/icons"
if git clone --depth 1 https://github.com/fursman/Desktop-Assets.git "$ASSETS_DIR" 2>/dev/null; then
    if [ -d "$ASSETS_DIR/Wallpaper/Donuts" ]; then
        mkdir -p "$HOME/Pictures/Wallpapers/Donuts"
        cp "$ASSETS_DIR/Wallpaper/Donuts"/*.jpg "$HOME/Pictures/Wallpapers/Donuts/" 2>/dev/null || true
        [ -f "$HOME/Pictures/Wallpapers/Donuts/1.jpg" ] && [ ! -f "$HOME/Pictures/Wallpapers/current.jpg" ] \
            && cp "$HOME/Pictures/Wallpapers/Donuts/1.jpg" "$HOME/Pictures/Wallpapers/current.jpg"
        success "Wallpapers installed"
    fi
    cp "$ASSETS_DIR/wlogout"/*.png "$HOME/.config/wlogout/icons/" 2>/dev/null \
        && success "wlogout icons installed" || warn "wlogout icons not found in assets"
else
    warn "Could not clone Desktop-Assets"
fi
rm -rf "$ASSETS_DIR"

# -- Flatpak --
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak install -y --noninteractive flathub org.gnome.World.PikaBackup 2>/dev/null \
    || warn "Pika Backup install skipped"

# -- GTK settings --
gsettings set org.gnome.desktop.interface gtk-theme     'Dracula'     2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme    'Dracula'     2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme  'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size   48            2>/dev/null || true

# -- Sysctl --
# swappiness=10: 64 GB of RAM, prefer dropping cache over swapping.
# inotify limits: the defaults are far too low for editors and file watchers.
if [ ! -f /etc/sysctl.d/99-desktop-tune.conf ]; then
    sudo tee /etc/sysctl.d/99-desktop-tune.conf >/dev/null <<'SYSEOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
SYSEOF
    sudo sysctl --system >/dev/null 2>&1
    success "sysctl tuning applied"
else
    info "sysctl tuning already present"
fi

# -- NVMe scheduler --
# NVMe has its own deep queues; an I/O scheduler on top only adds latency.
if [ ! -f /etc/udev/rules.d/60-io-scheduler.rules ]; then
    sudo tee /etc/udev/rules.d/60-io-scheduler.rules >/dev/null <<'UDEVEOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
UDEVEOF
    sudo udevadm control --reload-rules
    success "NVMe I/O scheduler rule installed"
fi

fi  # end CONFIGS_ONLY guard

# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  Hyprland desktop setup complete       ${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo ""
echo -e "  Log out and pick ${BOLD}Hyprland${NC} at the display manager."
echo -e "  ${BOLD}Super + Space${NC} shows the keybind cheatsheet."
echo ""
if pgrep -x Hyprland >/dev/null; then
    echo -e "  Already in Hyprland? Apply now without logging out:"
    echo -e "    ${CYAN}hyprctl reload${NC}"
    echo -e "    ${CYAN}pkill -SIGUSR2 waybar${NC}"
    echo ""
fi
