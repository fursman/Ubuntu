#!/bin/bash
set -e

# ============================================================================
# Stock Ubuntu -> Hyprland Setup Script
# Transforms stock Ubuntu 25.10 into a fully configured Hyprland desktop
# ============================================================================

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[  OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }
step()    { echo -e "\n${CYAN}${BOLD}-- $1 --${NC}"; }

echo -e "${BOLD}${CYAN}"
echo "  H Y P R L A N D"
echo -e "${NC}"
echo -e "${BOLD}  Stock Ubuntu -> Hyprland Desktop${NC}"
echo ""

# -- Step 1: APT packages --
step "1/10 - Installing APT packages"
sudo apt update
sudo apt install -y \
    hyprland waybar kitty rofi mako-notifier swaylock swayosd gtklock \
    grim slurp wl-clipboard cliphist \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    sway-notification-center swayidle wf-recorder wlogout \
    thunar thunar-volman pavucontrol \
    brightnessctl playerctl pamixer \
    btop fastfetch mpv vlc imagemagick \
    gnome-keyring seahorse network-manager-gnome blueman \
    papirus-icon-theme fonts-jetbrains-mono \
    espeak portaudio19-dev libportaudio2 python3-dev python3-venv \
    git curl wget flatpak hyprpaper
success "APT packages installed"

# -- Step 2: NVIDIA driver (auto-detect) --
step "2/10 - NVIDIA driver"
if lspci | grep -qi 'nvidia'; then
    if nvidia-smi &>/dev/null; then
        warn "NVIDIA driver already installed ($(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1))"
    else
        info "NVIDIA GPU detected, installing driver..."
        sudo apt install -y nvidia-driver-590-open linux-modules-nvidia-590-open-generic-hwe-24.04 || \
            warn "NVIDIA driver install failed -- you may need to reboot and retry"
    fi
else
    info "No NVIDIA GPU detected, skipping driver install"
fi
success "NVIDIA driver step complete"

# -- Step 3: Node.js 22 --
step "3/10 - Installing Node.js 22"
if command -v node &>/dev/null && node -v | grep -q "v22"; then
    warn "Node.js 22 already installed, skipping"
else
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt install -y nodejs
fi
success "Node.js $(node -v 2>/dev/null || echo 'pending') ready"

# -- Step 4: JetBrainsMono Nerd Font --
step "4/10 - Installing JetBrainsMono Nerd Font"
FONT_DIR="$HOME/.local/share/fonts"
if ls "$FONT_DIR"/JetBrainsMonoNerd* &>/dev/null; then
    warn "JetBrainsMono Nerd Font already installed, skipping"
else
    mkdir -p "$FONT_DIR"
    NERD_VERSION="v3.4.0"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/JetBrainsMono.tar.xz" -o /tmp/JetBrainsMono.tar.xz
    tar -xf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR"
    rm -f /tmp/JetBrainsMono.tar.xz
    fc-cache -fv
fi
success "Nerd Font installed"

# -- Step 5: Dracula GTK theme --
step "5/10 - Installing Dracula GTK theme"
if [ -d "$HOME/.themes/Dracula" ]; then
    warn "Dracula GTK theme already installed, skipping"
else
    git clone https://github.com/dracula/gtk.git "$HOME/.themes/Dracula"
fi
success "Dracula GTK theme ready"

# -- Step 6: Dracula icon theme --
step "6/10 - Installing Dracula icon theme"
if [ -d "$HOME/.icons/Dracula" ]; then
    warn "Dracula icon theme already installed, skipping"
else
    git clone https://github.com/m4thewz/dracula-icons.git /tmp/dracula-icons
    mkdir -p "$HOME/.icons/Dracula"
    cp -r /tmp/dracula-icons/* "$HOME/.icons/Dracula/"
    rm -rf /tmp/dracula-icons
fi
success "Dracula icon theme ready"

# -- Step 7: Deploy config files --
step "7/10 - Deploying configuration files"
declare -A CONFIG_MAP=(
    ["configs/hypr/hyprland.conf"]="$HOME/.config/hypr/hyprland.conf"
    ["configs/hypr/hyprpaper.conf"]="$HOME/.config/hypr/hyprpaper.conf"
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

# Rofi theme goes to share directory
mkdir -p "$HOME/.local/share/rofi/themes"
cp "$SCRIPT_DIR/configs/rofi/spotlight-dark.rasi" "$HOME/.local/share/rofi/themes/spotlight-dark.rasi"
info "-> ~/.local/share/rofi/themes/spotlight-dark.rasi"

# Fix wlogout icon paths (CSS doesn't expand ~ so we use absolute paths)
sed -i "s|/HOME_DIR|$HOME|g" "$HOME/.config/wlogout/style.css"
info "-> Fixed wlogout icon paths for $HOME"

# Generate NVIDIA env-local.conf (machine-specific GPU config)
ENV_LOCAL="$HOME/.config/hypr/env-local.conf"
info "Generating $ENV_LOCAL for this machine..."
cat > "$ENV_LOCAL" << 'ENVEOF'
# Auto-generated by setup.sh -- machine-specific environment overrides
# Edit this file for GPU-specific settings; it won't be overwritten by config deploys
ENVEOF

if lspci | grep -qi 'nvidia'; then
    cat >> "$ENV_LOCAL" << 'ENVEOF'
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
ENVEOF
    # Multi-GPU: detect all DRM card nodes and list them
    CARDS=$(ls /dev/dri/card* 2>/dev/null | sort | tr '\n' ':' | sed 's/:$//')
    if [ -n "$CARDS" ] && [ "$(echo "$CARDS" | tr ':' '\n' | wc -l)" -gt 1 ]; then
        echo "env = WLR_DRM_DEVICES,$CARDS" >> "$ENV_LOCAL"
        info "Multi-GPU detected: WLR_DRM_DEVICES=$CARDS"
    fi
    success "NVIDIA env vars written to env-local.conf"
else
    info "No NVIDIA GPU -- env-local.conf left empty"
fi

success "Config files deployed"

# -- Step 8: Helper scripts --
step "8/10 - Installing helper scripts"
mkdir -p "$HOME/.local/bin"
for script in "$SCRIPT_DIR"/scripts/*; do
    name="$(basename "$script")"
    cp "$script" "$HOME/.local/bin/$name"
    chmod +x "$HOME/.local/bin/$name"
    info "-> ~/.local/bin/$name"
done

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    info "Added ~/.local/bin to PATH in .bashrc"
fi
success "Helper scripts installed"

# -- Step 9: GTK theme settings --
step "9/10 - Setting GTK theme"
gsettings set org.gnome.desktop.interface gtk-theme 'Dracula' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Dracula' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size 48 2>/dev/null || true
success "GTK theme configured"

# -- Step 10: Flatpak apps --
step "10/10 - Installing Flatpak apps"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak install -y flathub org.gnome.World.PikaBackup 2>/dev/null || warn "Pika Backup install failed (try manually)"
success "Flatpak apps installed"

# -- Desktop assets (wallpaper + wlogout icons) --
step "Bonus - Desktop assets from github.com/fursman/desktop-assets"

ASSETS_DIR="/tmp/desktop-assets-setup"
ASSETS_URL="https://github.com/fursman/Desktop-Assets.git"

if [ ! -d "$ASSETS_DIR" ]; then
    git clone --depth 1 "$ASSETS_URL" "$ASSETS_DIR"
fi

# Wallpaper -- Donuts collection, use 1.jpg as default
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALLPAPER_DIR/Donuts"
if [ -d "$ASSETS_DIR/Wallpaper/Donuts" ]; then
    cp "$ASSETS_DIR/Wallpaper/Donuts"/*.jpg "$WALLPAPER_DIR/Donuts/" 2>/dev/null || true
    # Set first donut as the active wallpaper
    if [ -f "$WALLPAPER_DIR/Donuts/1.jpg" ]; then
        cp "$WALLPAPER_DIR/Donuts/1.jpg" "$WALLPAPER_DIR/current.jpg"
        success "Donut wallpaper set (8 variants in ~/Pictures/Wallpapers/Donuts/)"
    fi
else
    warn "Could not find Donuts wallpapers in desktop-assets"
fi

# wlogout icons
WLOGOUT_ICONS="$HOME/.config/wlogout/icons"
mkdir -p "$WLOGOUT_ICONS"
if [ -d "$ASSETS_DIR/wlogout" ]; then
    cp "$ASSETS_DIR/wlogout"/*.png "$WLOGOUT_ICONS/" 2>/dev/null || true
    success "wlogout icons installed"
else
    warn "Could not find wlogout icons in desktop-assets"
fi

rm -rf "$ASSETS_DIR"

# -- Done --
echo ""
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  Hyprland desktop setup complete!      ${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo ""
echo -e "  ${CYAN}Log out and select ${BOLD}Hyprland${NC}${CYAN} from your display manager.${NC}"
echo -e "  ${CYAN}Press ${BOLD}Super + Space${NC}${CYAN} for the keybind cheatsheet.${NC}"
echo ""
