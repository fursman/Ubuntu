# 🖥️ Ubuntu → Hyprland

**Stock Ubuntu to Hyprland desktop — one script setup.**

Transform a fresh Ubuntu 25.10 install into a fully configured, Dracula-themed Hyprland tiling compositor desktop with one command.

![Screenshot placeholder](https://via.placeholder.com/1920x1080/282a36/f8f8f2?text=Your+Desktop+Here)

## ✨ What's Included

| Component | Tool |
|-----------|------|
| Compositor | **Hyprland** — dynamic tiling Wayland compositor |
| Status Bar | **Waybar** — highly customizable bar |
| Terminal | **Kitty** — GPU-accelerated terminal |
| Launcher | **Rofi** — spotlight-style app launcher |
| File Manager | **Thunar** — lightweight file manager |
| Notifications | **SwayNC** — notification center |
| Lock Screen | **gtklock** — blurred screenshot lock |
| Logout Menu | **wlogout** — graphical session menu |
| Clipboard | **cliphist** — clipboard history with Rofi |
| Screenshots | **grim + slurp** — region/full capture |
| Recording | **wf-recorder** — screen recording |
| Theme | **Dracula** — GTK + icons |
| Font | **JetBrainsMono Nerd Font** |
| Wallpaper | **hyprpaper** |

## 📋 Prerequisites

- **Ubuntu 25.10** (Questing Quokka)
- **NVIDIA GPU** (script installs driver 590-open; edit for other GPUs)
- Fresh install recommended (safe to run on existing systems too)

## 🚀 Quick Start

```bash
git clone https://github.com/fursman/Ubuntu.git
cd Ubuntu
chmod +x setup.sh
./setup.sh
```

Log out, select **Hyprland** from your display manager, and enjoy.

## ⌨️ Keybinds

Press **Super + Space** to see all keybinds in a searchable Rofi menu.

### Apps

| Key | Action |
|-----|--------|
| `Super + Enter` | App Launcher (Rofi) |
| `Super + T` | Terminal (Kitty) |
| `Super + B` | Firefox |
| `Super + Alt + B` | Chromium |
| `Super + F` | File Manager (Thunar) |
| `Super + A` | Audio Settings |
| `Super + K` | Passwords (Seahorse) |

### Windows

| Key | Action |
|-----|--------|
| `Super + Q` | Close Window |
| `Super + Escape` | Fullscreen |
| `Super + Shift + F` | Toggle Floating |
| `Super + Shift + P` | Pin (Always on Top) |
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
| `Super + 1-0` | Switch Workspace |
| `Super + Shift + 1-0` | Move to Workspace |
| `Super + Scroll` | Cycle Workspaces |
| `3-Finger Swipe` | Swipe Workspaces |
| `` Super + ` `` | Dropdown Terminal |

### Screenshots & Recording

| Key | Action |
|-----|--------|
| `Print` | Full Screen → Clipboard |
| `Super + F12` | Full Screen → File |
| `Super + Shift + S` | Region → Clipboard |
| `Super + Shift + R` | Record Region (toggle) |
| `Super + Alt + R` | Record Full Screen (toggle) |

### Utilities

| Key | Action |
|-----|--------|
| `Super + V` | Clipboard History |
| `Super + N` | Notification Center |
| `Super + Shift + C` | Color Picker |
| `Super + L` | Lock Screen |
| `Super + X` | Logout Menu |

## 📁 Structure

```
.
├── setup.sh                    # Main setup script
├── configs/
│   ├── hypr/
│   │   ├── hyprland.conf       # Hyprland compositor config
│   │   └── hyprpaper.conf      # Wallpaper config
│   ├── waybar/
│   │   ├── config.jsonc        # Waybar modules
│   │   └── style.css           # Waybar styling
│   ├── kitty/kitty.conf        # Terminal config
│   ├── rofi/
│   │   ├── config.rasi         # Rofi config
│   │   └── spotlight-dark.rasi # Rofi theme
│   ├── mako/config             # Notification config
│   ├── wlogout/
│   │   ├── layout              # Logout menu layout
│   │   └── style.css           # Logout menu style
│   ├── gtklock/style.css       # Lock screen style
│   ├── swaync/
│   │   ├── config.json         # Notification center config
│   │   └── style.css           # Notification center style
│   ├── gtk-3.0/settings.ini    # GTK3 theme
│   └── gtk-4.0/settings.ini    # GTK4 theme
└── scripts/
    ├── lock-screen             # Blur-lock script
    └── hypr-cheatsheet         # Keybind cheatsheet
```

## ⚠️ Notes

- **wlogout icons**: You need to provide your own PNG icons at `~/.config/wlogout/icons/` (1.png through 6.png: lock, logout, suspend, hibernate, shutdown, reboot)
- **Wallpaper**: The setup downloads a Dracula wallpaper. Replace `~/Pictures/Wallpapers/current.jpg` with your own
- **NVIDIA**: The script installs driver 590-open. Edit `setup.sh` if you have a different GPU
- The script is **idempotent** — safe to run multiple times

## 🙏 Credits

- [Hyprland](https://hyprland.org/) — Wayland compositor
- [Dracula Theme](https://draculatheme.com/) — GTK theme & icons
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/) — Font
- [Nerd Fonts](https://www.nerdfonts.com/) — Patched fonts with icons

## 📄 License

MIT
