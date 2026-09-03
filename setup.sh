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

# Does a command's output match a pattern? Use this instead of `cmd | grep -q`.
#
# Under `set -o pipefail` that pipeline is a trap. grep -q exits at the FIRST
# match, the still-running producer takes SIGPIPE, and the pipeline reports 141
# -- so a successful match reads as a failed test. It bites the slow hardware
# enumerators specifically (lspci, lsusb, dmidecode, udevadm, ufw): they are
# still walking the bus when grep has already found what it wanted.
#
# Worse than a clean break, it is a race, so the same line works on one machine
# and silently skips its step on another. That is exactly how a box with two
# NVIDIA cards ended up with no NVIDIA env vars in its Hyprland config, and how
# `elif ! lspci | grep -qi nvidia` could decide an NVIDIA machine had no GPU and
# skip the driver install entirely.
#
# Capturing the output first means no pipe, so nothing can be signalled.
out_matches() {
    local pattern="$1"; shift
    local output
    output="$("$@" 2>/dev/null || true)"
    grep -qiE -- "$pattern" <<<"$output"
}

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
# Drop PPA entries left pointing at a PREVIOUS release. do-release-upgrade
# rewrites the archive sources but leaves a third-party .sources file naming
# the old codename, and that series no longer resolves -- so Hyprland is simply
# not available at upgrade time and the upgrade REMOVES it. That is not
# hypothetical: a 25.10 -> 26.04 upgrade here dropped hyprland outright because
# its PPA still said `questing`, which would have booted the machine to a
# display manager with no compositor behind it.
for stale in /etc/apt/sources.list.d/cppiber-ubuntu-hyprland-*.sources; do
    [ -e "$stale" ] || continue
    case "$stale" in
        *"-$CODENAME.sources") ;;
        *) sudo rm -f "$stale"
           warn "Removed stale Hyprland PPA entry: $(basename "$stale")" ;;
    esac
done

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
# Preferred: mate-polkit. It is the maintained fork of polkit-gnome's GTK
# dialog (polkit-gnome 0.105 itself segfaults on 26.04), and it draws a far
# nicer prompt than hyprpolkitagent's Qt one. On 26.04 its agent sits at a
# predictable /usr/libexec path.
if apt-cache show mate-polkit >/dev/null 2>&1; then
    apt_need mate-polkit
    POLKIT_AGENT="/usr/libexec/polkit-mate-authentication-agent-1"
elif apt-cache show hyprpolkitagent >/dev/null 2>&1; then
    apt_need hyprpolkitagent
    POLKIT_AGENT="/usr/libexec/hyprpolkitagent"
else
    apt_need lxpolkit
    POLKIT_AGENT="/usr/bin/lxpolkit"
fi

# -- Desktop services and apps --
apt_need thunar thunar-volman tumbler pavucontrol \
         brightnessctl playerctl pamixer \
         gnome-keyring seahorse network-manager-gnome blueman \
         btop fastfetch mpv imagemagick ffmpeg \
         papirus-icon-theme fonts-jetbrains-mono fonts-font-awesome \
         git git-lfs gh curl wget flatpak timeshift \
         python3-pyatspi

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
if out_matches 'Razer' lsusb || out_matches razer sudo dmidecode -s system-manufacturer; then
    apt_need openrazer-meta python3-openrazer
    sudo usermod -aG plugdev "$USER" 2>/dev/null || true
    success "OpenRazer installed"
else
    info "No Razer hardware detected, skipping"
fi

step "4/10 - NVIDIA driver"
if [ "$SKIP_NVIDIA" = 1 ]; then
    info "--no-nvidia given, skipping"
elif ! out_matches 'nvidia' lspci; then
    info "No NVIDIA GPU detected, skipping"
else
    # Prefer the DISTRO-SIGNED prebuilt modules over DKMS. They survive
    # Secure Boot, and they do not need rebuilding on every kernel bump —
    # which is what silently breaks a DKMS setup after an unattended upgrade.
    #
    # We take the `-open` flavour, which is what ubuntu-drivers steers every
    # supported GPU to from driver 560 onward. One caveat worth knowing:
    # NVIDIA's open modules only implement Run Time D3 power gating on
    # Ampere and newer. On a pre-Ampere laptop `-open` therefore costs you
    # dGPU power-down and battery life, and the proprietary flavour (same
    # number, no `-open` suffix) is the better choice.
    if out_matches 'NVIDIA.*\[10de:1[e-f][0-9a-f]{2}\]' lspci -nn; then
        warn "Pre-Ampere (Turing) GPU detected."
        warn "The -open driver has no RTD3 power gating below Ampere; consider"
        warn "installing the proprietary flavour instead (no -open suffix)."
    fi

    # `|| true` because this pipeline ends in `head -1`: head exits after the
    # first line, grep takes SIGPIPE, and under `set -o pipefail` the
    # substitution reports 141 -- which `set -e` turns into an abort of the
    # whole script, on a line that actually succeeded. Same trap as the
    # detection helper above, and it is a race, so it fails on some machines
    # and not others. The empty-result path below is the real fallback.
    NV_VER=$(ubuntu-drivers devices 2>/dev/null \
             | awk '/recommended/ {print $3}' | grep -oP 'nvidia-driver-\K[0-9]+' | head -1 || true)
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
for d in swaync wlogout gtklock; do
    mkdir -p "$HOME/.config/$d"
    cp "$SCRIPT_DIR/configs/theme/dracula.css" "$HOME/.config/$d/palette.css"
done
info "-> palette.css deployed to swaync, wlogout, gtklock"

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
    out_matches 'platform-simple-framebuffer' udevadm info "$card" && continue
    DRM_CARDS="${DRM_CARDS:+$DRM_CARDS:}$card"
done

cat > "$ENV_LOCAL" <<EOF
# Auto-generated by setup.sh — machine-specific environment overrides.
# Safe to edit: config redeploys do not overwrite this file's siblings.
# DRM devices detected: $DRM_CARDS
env = WLR_DRM_DEVICES,$DRM_CARDS
EOF

if out_matches 'nvidia' lspci; then
    cat >> "$ENV_LOCAL" <<'ENVEOF'

# NVIDIA
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia
ENVEOF
    info "NVIDIA env vars written"
elif out_matches 'intel.*graphics' lspci; then
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

# Razer per-key RGB: a calm warm-white backlight, and the CapsLock key turns
# red while caps-sudo has passwordless sudo armed. Wired here rather than in
# the Razer step because the unit runs ~/.local/bin/keyboard-ambient, which
# only exists after the install loop above.
#
# keyboard-fire is the same repo's flame effect. Only one process may own the
# key matrix, so the two units Conflict=; ambient is the default because it is
# readable at night without the motion. `systemctl --user enable --now
# keyboard-fire` brings the flames back.
AMBIENT_UNIT="$SCRIPT_DIR/caps-sudo/indicator/razer/keyboard-ambient.service"
if [ "$CONFIGS_ONLY" = 0 ] && [ -f "$AMBIENT_UNIT" ] && \
   { out_matches 'Razer' lsusb || out_matches razer sudo dmidecode -s system-manufacturer; }; then
    mkdir -p "$HOME/.config/systemd/user"
    install -m 0644 "$AMBIENT_UNIT" "$HOME/.config/systemd/user/keyboard-ambient.service"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user disable --now keyboard-fire.service 2>/dev/null || true
    if systemctl --user enable --now keyboard-ambient.service 2>/dev/null; then
        info "-> keyboard-ambient.service (CapsLock lights red while sudo is armed)"
    else
        warn "Could not start keyboard-ambient.service (is openrazer-daemon running?)"
    fi
fi

# Voice assistant. The waybar config ships a custom/voice module, so without
# this unit that module renders permanently empty on a fresh install. The
# project itself is a separate repo (it carries its own venv and a ~300MB ONNX
# model) and is deliberately NOT vendored here -- clone it to ~/voice-assistant
# and this step picks it up. Absent, we skip silently.
# The unit ships WITH that project, not here — keeping a second copy in this
# repo just means the two drift, and the stale one wins whenever setup.sh runs.
VOICE_UNIT="$HOME/voice-assistant/voice-assistant.service"
if [ "$CONFIGS_ONLY" = 0 ] && [ -f "$VOICE_UNIT" ] && [ -x "$HOME/.local/bin/voice-assistant" ]; then
    mkdir -p "$HOME/.config/systemd/user"
    install -m 0644 "$VOICE_UNIT" "$HOME/.config/systemd/user/voice-assistant.service"
    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable --now voice-assistant.service 2>/dev/null; then
        info "-> voice-assistant.service"
    else
        warn "Could not start voice-assistant.service (check: journalctl --user -u voice-assistant)"
    fi
elif [ -f "$VOICE_UNIT" ] && [ ! -x "$HOME/.local/bin/voice-assistant" ]; then
    info "voice-assistant not installed — skipping its unit (waybar's voice module stays idle)"
fi

# AppArmor parser concurrency cap. apparmor_parser defaults to -j nproc, and the
# 5.0.x parser shipped with 26.04 corrupts its heap above ~12 parallel jobs: the
# workers SIGABRT and the parent then blocks forever on dead children, at 0% CPU.
# On a 32-thread machine this hung the release upgrade's apparmor.postinst for
# 82 minutes and cascaded into a half-configured system. Cap it before it can
# ever run. Harmless on small machines; jobs=8 parses the full profile set in
# ~2s on a 64-thread box. Ubuntu bug worth filing; this is the workaround.
if ! grep -qE '^jobs=' /etc/apparmor/parser.conf 2>/dev/null; then
    sudo mkdir -p /etc/apparmor
    echo 'jobs=8' | sudo tee -a /etc/apparmor/parser.conf >/dev/null
    info "Capped apparmor_parser to 8 jobs (parallel-parse hang on many-core CPUs)"
fi

# Record which polkit agent to launch, so hyprland.conf can stay generic.
#
# POLKIT_AGENT is only set by the package step, which --configs-only skips, so
# the fallback list below has to be able to find an agent on its own. It has to
# include mate-polkit for that reason: it is the PREFERRED agent, installed
# above, and leaving it out of this list meant a redeploy on a machine that
# already had it wrote an empty file and warned that no agent existed. Order
# matches the install preference.
mkdir -p "$HOME/.config/hypr"
POLKIT_CANDIDATES=(
    "${POLKIT_AGENT:-}"
    /usr/libexec/polkit-mate-authentication-agent-1
    /usr/lib/mate-polkit/polkit-mate-authentication-agent-1
    /usr/libexec/hyprpolkitagent
    /usr/bin/lxpolkit
)
POLKIT_FOUND=""
for agent in "${POLKIT_CANDIDATES[@]}"; do
    [ -n "$agent" ] && [ -x "$agent" ] && { POLKIT_FOUND="$agent"; break; }
done
# Machine-local overrides, sourced LAST by hyprland.conf so they win. Created
# once and never rewritten -- unlike env-local.conf, whose contents this script
# derives from the hardware, this one holds things only a human knows. A config
# redeploy that silently reverted such a fix is what motivated it.
HYPR_LOCAL="$HOME/.config/hypr/local.conf"
if [ -f "$HYPR_LOCAL" ]; then
    info "-> ~/.config/hypr/local.conf (kept, not overwritten)"
else
    cat > "$HYPR_LOCAL" <<'LOCALEOF'
# Machine-local Hyprland overrides. Sourced last, so anything here beats the
# shared config. setup.sh creates this file once and never overwrites it.
#
# Example -- needed when the display hangs off one of several GPUs, where
# hardware cursor planes fail with "Backend requires blit, but cursor blit
# failed" and the screen appears to freeze:
#
# cursor {
#     no_hardware_cursors = true
# }
LOCALEOF
    info "-> ~/.config/hypr/local.conf (created)"
fi

if [ -n "$POLKIT_FOUND" ]; then
    echo "exec-once = $POLKIT_FOUND" > "$HOME/.config/hypr/polkit-local.conf"
    info "Polkit agent: $POLKIT_FOUND"
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

    # Same problem one layer up: hyprpolkitagent ships an ENABLED user unit and
    # would grab org.freedesktop.PolicyKit1.AuthenticationAgent before
    # polkit-local.conf's exec-once runs, so the Qt prompt would win the race
    # even though mate-polkit is the configured agent. Only mask it when
    # mate-polkit is the one we actually picked.
    case "${POLKIT_AGENT:-}" in
        *polkit-mate-authentication-agent-1)
            systemctl --user mask hyprpolkitagent.service 2>/dev/null \
                && info "Masked hyprpolkitagent.service (mate-polkit is the agent)" || true
            ;;
    esac
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
flatpak install -y --noninteractive flathub org.gnome.NetworkDisplays 2>/dev/null \
    || warn "GNOME Network Displays install skipped"

# -- Wireless display (Miracast) firewall --
# Counterintuitive but load-bearing: GNOME Network Displays runs the RTSP
# SERVER and the TV connects IN to port 7236. A default-deny-incoming firewall
# therefore kills mirroring with no useful error.
#
# GND can only auto-open ports through firewalld, which is not installed here;
# it logs "Firewalld does not seem to be installed" and carries on as though
# the ports were open. So the rules have to be added by hand.
# See docs/WIRELESS-DISPLAY.md.
if command -v ufw >/dev/null 2>&1 && out_matches '^Status: active' sudo ufw status; then
    if out_matches '7236' sudo ufw status; then
        info "Miracast firewall rules already present"
    else
        sudo ufw allow 7236/tcp comment 'Miracast RTSP (gnome-network-displays)' >/dev/null
        sudo ufw allow 7236/udp comment 'Miracast RTSP/UDP'                      >/dev/null
        sudo ufw allow 5353/udp comment 'mDNS discovery'                         >/dev/null
        success "Miracast firewall rules added (7236/tcp, 7236/udp, 5353/udp)"
    fi
else
    info "ufw not active — no Miracast firewall rules needed"
fi

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
