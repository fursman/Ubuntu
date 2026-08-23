# Ubuntu -> Hyprland

**Stock Ubuntu to Hyprland desktop -- one script setup.**

Transform a fresh Ubuntu **26.04 LTS** install into a fully configured, Dracula-themed
Hyprland tiling compositor desktop with one command.

Two scripts live here, deliberately separate:

| Script | Scope | Safe anywhere? |
|---|---|---|
| `setup.sh` | The desktop. Portable across machines. | Yes |
| `gpu-passthrough.sh` | Single-GPU VFIO passthrough, Looking Glass, and a Windows VM. Razer Blade Pro 17 specific, changes boot config. | No -- read [docs/GPU-PASSTHROUGH.md](docs/GPU-PASSTHROUGH.md) first |

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
| Wallpaper | **awww** -- animated wallpaper daemon, Donut collection from [desktop-assets](https://github.com/fursman/Desktop-Assets) |
| Idle/Lock | **swayidle** -- auto-lock at 60 min, DPMS off at 61 min, lock before sleep |
| Annotation | **swappy** -- mark up a region grab without leaving the keyboard |
| Auth prompts | **hyprpolkitagent** -- polkit agent, so privilege prompts actually appear |
| Snapshots | **Timeshift** -- rsync system snapshots for rollback |
| Wireless display | **GNOME Network Displays** -- Miracast mirroring to a TV, see [docs/WIRELESS-DISPLAY.md](docs/WIRELESS-DISPLAY.md) |

## Prerequisites

- **Ubuntu 26.04 LTS** (Resolute Raccoon). The release codename is resolved at
  runtime, so the script also works on later releases the Hyprland PPA supports.
- Fresh install recommended, but the script is idempotent and safe to re-run.
- NVIDIA GPUs are auto-detected. The script asks `ubuntu-drivers` which driver
  is recommended rather than pinning a version, and prefers the distro-signed
  prebuilt kernel modules over DKMS so the driver survives kernel upgrades.

## Quick Start

```bash
git clone https://github.com/fursman/Ubuntu.git
cd Ubuntu
chmod +x setup.sh
./setup.sh
```

Log out, select **Hyprland** from your display manager, and log back in.

Press **Super + Space** for a searchable keybind cheatsheet.

Useful flags:

```bash
./setup.sh --configs-only   # redeploy dotfiles + theme only, install nothing
./setup.sh --no-nvidia      # skip the GPU driver step
```

Already in a Hyprland session? Apply a config redeploy without logging out:

```bash
hyprctl reload && pkill -SIGUSR2 waybar
```

## Setup Steps

All steps are idempotent -- each checks what is already installed and only does
the missing work, so re-running is fast and quiet.

1. **Repositories** -- adds the Hyprland PPA for the *detected* release codename,
   falling back to the archive if that series does not exist yet
2. **Packages** -- compositor, bar, launcher, portals, notification centre,
   polkit agent, toolchain
3. **Razer hardware** -- OpenRazer, only if Razer hardware is actually present
4. **NVIDIA driver** -- recommended version via `ubuntu-drivers`, signed prebuilt
   modules, then `apt-mark manual` so `autoremove` cannot orphan it
5. **Node.js 22** -- via NodeSource
6. **Fonts** -- JetBrainsMono Nerd Font v3.4.0
7. **GTK/icon theme** -- Dracula
8. **Config files** -- dotfiles, the shared colour palette, and a machine-local
   `env-local.conf` holding GPU-specific environment
9. **Helper scripts + session wiring** -- `~/.local/bin` scripts, polkit agent
   selection, masking `mako` so it cannot fight swaync for the notification bus
10. **Wallpaper daemon, assets, tuning** -- builds `awww`, pulls wallpapers and
    wlogout icons, applies sysctl and NVMe scheduler tuning

### Why `sway-notification-center` is no longer built from source

Ubuntu 26.04 ships `sway-notification-center 0.12.4` -- the exact version this
setup used to compile by hand. The whole meson/ninja build step is gone.

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
| `Super + Shift + A` | Region -> Annotate (Swappy) |
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

Also on `PATH`: `wireless-display` (Miracast mirroring), `wallpaper-cycle`,
`restart-waybar`, `hypr-cheatsheet`.

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
├── setup.sh                       # Desktop setup (portable)
├── gpu-passthrough.sh             # VFIO + Looking Glass + Windows VM (Blade 17)
├── docs/
│   ├── GPU-PASSTHROUGH.md         # Why every passthrough knob exists
│   └── WIRELESS-DISPLAY.md        # Miracast: the protocol and the 3 gotchas
├── configs/
│   ├── theme/dracula.css          # THE palette — every stylesheet imports this
│   ├── hypr/hyprland.conf         # Compositor (sources env-local + polkit-local)
│   ├── waybar/{config.jsonc,style.css}
│   ├── kitty/kitty.conf
│   ├── rofi/{config.rasi,spotlight-dark.rasi}
│   ├── mako/config
│   ├── swaync/{config.json,style.css}
│   ├── wlogout/{layout,style.css}
│   ├── gtklock/style.css
│   └── gtk-{3.0,4.0}/settings.ini
├── passthrough/                   # Verbatim artifacts from the live host
│   ├── grub.d/40_gpu-passthrough  # Generates the second boot entry
│   ├── modprobe.d/{vfio,kvmfr}.conf
│   ├── modules-load.d/kvmfr.conf
│   ├── sysctl.d/99-hugepages.conf
│   ├── udev/*.rules               # kvmfr perms, 8BitDo, governor, USB wake
│   ├── acpi/ssdt-battery.asl      # Fake battery (recompilable source)
│   ├── vm/win10-lg.xml            # libvirt domain
│   ├── bin/{8bitdo-passthrough,dump-vbios.sh}
│   └── assets/                    # vBIOS lives here, gitignored
└── scripts/                       # Installed to ~/.local/bin
    ├── lock-screen
    ├── wireless-display
    ├── hypr-cheatsheet
    ├── restart-waybar
    ├── wallpaper-cycle
    ├── open-network-settings
    └── open-bluetooth-settings
```

## Theming

Every GTK-CSS surface -- waybar, swaync, wlogout, gtklock -- imports the same
palette from `configs/theme/dracula.css`, which defines the Dracula colours once
as `@define-color` names plus a few documented translucent derivatives.

GTK CSS has no `~` expansion and no import search path, so `setup.sh` copies the
palette next to each stylesheet as `palette.css`. To retheme the entire desktop,
edit that one file and re-run `./setup.sh --configs-only`.

Two conventions keep it coherent:

- **Accents carry meaning.** A module is coloured by its domain (connectivity
  cyan, compute purple, power green, brightness yellow), and only shifts to
  orange/red when it wants attention.
- **One radius, one gap.** Every pill is `10px` with a `5px` vertical margin, so
  bar height stays uniform regardless of which modules are enabled.

### A note on sizing

The reference machine is a 17" 3840x2160 panel running at **scale 1.0** (~257
DPI), so type in the stylesheets is specified deliberately large (19-26px). If
you set a monitor scale in `hyprland.conf`, divide every px value in the
stylesheets by that scale.

## NVIDIA & Multi-GPU

`setup.sh` writes `~/.config/hypr/env-local.conf` with the environment your GPU
needs, and never overwrites it on a plain config redeploy:

- `GBM_BACKEND=nvidia-drm`
- `__GLX_VENDOR_LIBRARY_NAME=nvidia`
- `LIBVA_DRIVER_NAME=nvidia`
- `WLR_DRM_DEVICES` populated with every real DRM card node found

It also sets `options nvidia-drm modeset=1 fbdev=1`, which Wayland requires on
NVIDIA and which prevents a black screen between GRUB and the compositor.

Two details worth knowing, both learned the hard way:

- **Signed prebuilt modules, not DKMS.** `linux-modules-nvidia-<ver>-open-generic-hwe-*`
  works under Secure Boot and does not need rebuilding on every kernel bump. A
  DKMS build that silently fails after an unattended kernel upgrade is the usual
  cause of "it booted to a black screen and I changed nothing".
- **The driver metapackage is pinned `apt-mark manual`.** If it is only ever
  pulled in as a dependency, a later `apt autoremove` will happily orphan the
  whole driver stack.

## Customization

- **Colours**: edit `configs/theme/dracula.css`, then `./setup.sh --configs-only`
- **Wallpaper**: replace `~/Pictures/Wallpapers/current.jpg`, or cycle the Donut
  variants with `Home`/`End`
- **GPU config**: `~/.config/hypr/env-local.conf` (never overwritten by redeploys)
- **Keybinds**: `~/.config/hypr/hyprland.conf`, then `hyprctl reload`
- **Waybar modules**: `~/.config/waybar/config.jsonc`, then `pkill -SIGUSR2 waybar`

## Credits

- [Hyprland](https://hyprland.org/) -- Wayland compositor
- [Dracula Theme](https://draculatheme.com/) -- GTK theme & icons
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/) -- Typeface
- [Nerd Fonts](https://www.nerdfonts.com/) -- Patched fonts with icons
- [fursman/Desktop-Assets](https://github.com/fursman/Desktop-Assets) -- Wallpapers & wlogout icons

## License

MIT
