# Ubuntu -> Hyprland

**Stock Ubuntu to Hyprland desktop -- one script setup.**

Transform a fresh Ubuntu 25.10 install into a fully configured, Dracula-themed Hyprland tiling compositor desktop with one command.

## What's Included

| Component | Tool |
|-----------|------|
| Compositor | **Hyprland** -- dynamic tiling Wayland compositor |
| Status Bar | **Waybar** -- customizable status bar with system monitors |
| Terminal | **Kitty** -- GPU-accelerated terminal (50% transparent, blurred) |
| Launcher | **Rofi** -- macOS Spotlight-style app launcher |
| File Manager | **Thunar** -- lightweight file manager |
| Notifications | **SwayNC** -- Dracula-themed notification center |
| Lock Screen | **gtklock** -- blurred screenshot lock with Dracula styling |
| Logout Menu | **wlogout** -- graphical session menu (lock/logout/suspend/hibernate/shutdown/reboot) |
| Clipboard | **cliphist** -- clipboard history (text + images) via Rofi |
| Screenshots | **grim + slurp** -- region and full-screen capture |
| Recording | **wf-recorder** -- screen recording |
| OSD | **SwayOSD** -- on-screen display for volume, brightness, caps lock |
| Theme | **Dracula** -- GTK theme + icon theme |
| Font | **JetBrainsMono Nerd Font** |
| Wallpaper | **hyprpaper** -- with Donut collection from [desktop-assets](https://github.com/fursman/Desktop-Assets) |
| Idle/Lock | **swayidle** -- auto-lock at 5 min, DPMS off at 10 min, lock before sleep |

## Prerequisites

- **Ubuntu 25.10** (Questing Quokka)
- Fresh install recommended (safe to run on existing systems too)
- NVIDIA GPUs are auto-detected; the script installs driver 590-open if needed

## Quick Start

```bash
git clone https://github.com/fursman/Ubuntu.git
cd Ubuntu
chmod +x setup.sh
./setup.sh
```

Log out, select **Hyprland** from your display manager, and log back in.

Press **Super + Space** for a searchable keybind cheatsheet.

## Setup Steps

The script runs 10 steps, all idempotent (safe to re-run):

1. **APT packages** -- Hyprland, Waybar, Kitty, Rofi, grim, slurp, and ~40 more packages
2. **NVIDIA driver** -- auto-detected; installs 590-open if an NVIDIA GPU is present
3. **Node.js 22** -- via NodeSource
4. **JetBrainsMono Nerd Font** -- from nerd-fonts v3.4.0
5. **Dracula GTK theme** -- cloned from dracula/gtk
6. **Dracula icon theme** -- cloned from m4thewz/dracula-icons
7. **Config files** -- all configs deployed to `~/.config/`, plus machine-specific `env-local.conf` for NVIDIA/multi-GPU
8. **Helper scripts** -- lock-screen, cheatsheet, restart-waybar, network/bluetooth launchers
9. **GTK settings** -- Dracula theme, dark mode, cursor size via gsettings
10. **Flatpak apps** -- Pika Backup

Then downloads wallpapers (Donut collection) and wlogout icons from [fursman/Desktop-Assets](https://github.com/fursman/Desktop-Assets).

## Keybinds

Press **Super + Space** to see all keybinds in a searchable Rofi menu.

### Apps

| Key | Action |
|-----|--------|
| `Super + Enter` | App Launcher (Rofi) |
| `Super + T` | Terminal (Kitty) |
| `Super + B` | Firefox |
| `Super + Alt + B` | Chromium |
| `Super + F` | File Manager (Thunar) |
| `Super + A` | Audio Settings (pavucontrol) |
| `Super + S` | Signal |
| `Super + R` | Pika Backup |
| `Super + K` | Passwords (Seahorse) |

### Windows

| Key | Action |
|-----|--------|
| `Super + Q` | Close Window |
| `Super + Escape` | Fullscreen |
| `Super + Shift + F` | Toggle Floating |
| `Super + Shift + P` | Pin (Always on Top) |
| `Super + Shift + Space` | Center Window |
| `Super + P` | Pseudo-tile |
| `Super + J` | Toggle Split |
| `Super + G` | Group Windows |
| `Super + Tab` | Cycle Grouped |

### Move & Resize

| Key | Action |
|-----|--------|
| `Super + Arrow` | Focus Direction |
| `Super + Shift + Arrow` | Move Window |
| `Super + Ctrl + Arrow` | Resize Window |
| `Super + Drag LMB` | Move (Mouse) |
| `Super + Drag RMB` | Resize (Mouse) |

### Workspaces

| Key | Action |
|-----|--------|
| `Super + 1-0` | Switch Workspace 1-10 |
| `Super + Shift + 1-0` | Move Window to Workspace |
| `Super + Alt + 1-5` | Move Silently (don't follow) |
| `Super + Scroll` | Cycle Workspaces |
| `3-Finger Swipe` | Swipe Workspaces |
| `` Super + ` `` | Dropdown Terminal (scratchpad) |

### Screenshots & Recording

| Key | Action |
|-----|--------|
| `Print` | Full Screen -> Clipboard |
| `Super + F12` | Full Screen -> File |
| `Super + Shift + S` | Region -> Clipboard |
| `Super + Shift + F12` | Region -> File |
| `Super + Shift + R` | Record Region (toggle) |
| `Super + Alt + R` | Record Full Screen (toggle) |

### Utilities

| Key | Action |
|-----|--------|
| `Super + Space` | Keybind Cheatsheet |
| `Super + V` | Clipboard History |
| `Super + N` | Notification Center |
| `Super + Shift + C` | Color Picker |
| `Super + L` | Lock Screen |
| `Super + X` | Logout Menu |

### Media & Hardware Keys

| Key | Action |
|-----|--------|
| `Volume Up/Down/Mute` | Volume control (SwayOSD) |
| `Mic Mute` | Microphone toggle (SwayOSD) |
| `Caps Lock` | Caps indicator (SwayOSD) |
| `Brightness Up/Down` | Brightness control (SwayOSD) |
| `Play/Pause/Next/Prev` | Media control (playerctl) |

## Waybar

The status bar shows (left to right):

- **Left**: Workspace icons (10 persistent), taskbar
- **Center**: Active window title
- **Right**: System tray, network (with live bandwidth), bluetooth, disk, memory, CPU, temperature, audio, backlight, battery, date, time, media player, notifications

**Click actions:**
- Network icon -> network settings; right-click -> nm-connection-editor
- Bluetooth icon -> bluetooth settings; right-click -> toggle rfkill
- Notification icon -> toggle notification center

## Structure

```
.
├── setup.sh                    # Main setup script (10 steps + assets)
├── configs/
│   ├── hypr/
│   │   ├── hyprland.conf       # Compositor config (sources env-local.conf)
│   │   └── hyprpaper.conf      # Wallpaper config
│   ├── waybar/
│   │   ├── config.jsonc        # Status bar modules
│   │   └── style.css           # Status bar styling
│   ├── kitty/kitty.conf        # Terminal config
│   ├── rofi/
│   │   ├── config.rasi         # Launcher config
│   │   └── spotlight-dark.rasi # Spotlight-style dark theme
│   ├── mako/config             # Notification daemon (Dracula colors)
│   ├── swaync/
│   │   ├── config.json         # Notification center config
│   │   └── style.css           # Notification center (Dracula theme)
│   ├── wlogout/
│   │   ├── layout              # Logout menu (6 actions)
│   │   └── style.css           # Logout menu styling
│   ├── gtklock/style.css       # Lock screen (Dracula theme)
│   ├── gtk-3.0/settings.ini    # GTK3 theme settings
│   └── gtk-4.0/settings.ini    # GTK4 theme settings
└── scripts/
    ├── lock-screen             # Blurred-screenshot gtklock
    ├── hypr-cheatsheet         # Searchable keybind reference
    ├── restart-waybar          # Graceful waybar restart
    ├── open-network-settings   # Network settings launcher
    └── open-bluetooth-settings # Bluetooth settings launcher
```

## NVIDIA & Multi-GPU

The setup script auto-detects NVIDIA GPUs and generates `~/.config/hypr/env-local.conf` with the appropriate environment variables:

- `GBM_BACKEND=nvidia-drm`
- `__GLX_VENDOR_LIBRARY_NAME=nvidia`
- `LIBVA_DRIVER_NAME=nvidia`
- `WLR_NO_HARDWARE_CURSORS=1`

For multi-GPU systems, `WLR_DRM_DEVICES` is auto-populated with all detected DRM card nodes. Edit `env-local.conf` to adjust GPU priority or remove variables for non-NVIDIA setups.

## Customization

- **Wallpaper**: Replace `~/Pictures/Wallpapers/current.jpg` or pick from the 8 Donut variants in `~/Pictures/Wallpapers/Donuts/`
- **GPU config**: Edit `~/.config/hypr/env-local.conf` for machine-specific GPU settings
- **Keybinds**: Edit `~/.config/hypr/hyprland.conf`
- **Waybar modules**: Edit `~/.config/waybar/config.jsonc` and `style.css`

## Credits

- [Hyprland](https://hyprland.org/) -- Wayland compositor
- [Dracula Theme](https://draculatheme.com/) -- GTK theme & icons
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/) -- Typeface
- [Nerd Fonts](https://www.nerdfonts.com/) -- Patched fonts with icons
- [fursman/Desktop-Assets](https://github.com/fursman/Desktop-Assets) -- Wallpapers & wlogout icons

## License

MIT
