# Ubuntu -> Hyprland

**Stock Ubuntu to Hyprland desktop -- one script setup.**

Transform a fresh Ubuntu **26.04 LTS** install into a fully configured, themeable
Hyprland tiling compositor desktop with one command.

Many of the desktop's conveniences -- the system menu, quick settings, themes,
toggles, capture tools, screensaver -- are modelled on
[omarchy](https://github.com/basecamp/omarchy), DHH's Arch-based Hyprland
distribution, rebuilt here from Ubuntu packages (waybar, swaync, rofi, the
Hyprland PPA). Omarchy's themes work here unchanged: `desktop-theme sync`
fetches its whole collection.

Three scripts live here, deliberately separate:

| Script | Scope | Safe anywhere? |
|---|---|---|
| `setup.sh` | The desktop. Portable across machines. | Yes |
| `gpu-passthrough.sh` | Single-GPU VFIO passthrough, Looking Glass, and a Windows VM. Razer Blade Pro 17 specific, changes boot config. | No -- read [docs/GPU-PASSTHROUGH.md](docs/GPU-PASSTHROUGH.md) first |
| `caps-sudo/install.sh` | Makes CapsLock arm/disarm passwordless `sudo`, with the CapsLock LED as the "armed" light. Grants root without a password while armed. | No -- read [docs/CAPS-SUDO.md](docs/CAPS-SUDO.md) first |
| `llm-serve/install.sh` | Serves Qwen3.8-27B on one 24GB NVIDIA GPU: builds llama.cpp with CUDA, downloads ~17.6GB, runs an OpenAI-compatible API + web UI on :8081. | Needs an NVIDIA GPU; API is unauthenticated by default -- read [llm-serve/README.md](llm-serve/README.md) |
| `macbook/install.sh` | MacBook Pro quirks, three of them: stops PipeWire suspending the CS8409 sound card (closing playback freezes the microphone); makes libinput palm rejection work at all (the applespi keyboard reports no vendor id, so disable-while-typing never engages); and powers off on lid close, because no sleep mode on this hardware resumes. **`setup.sh` runs this by itself when the DMI vendor is Apple**, so a fresh install needs no extra step. | Yes -- inert on other hardware, and `--remove` undoes it. Read [macbook/README.md](macbook/README.md) first: the third fix masks the sleep targets. |

## What's Included

| Component | Tool |
|-----------|------|
| Compositor | **Hyprland** -- dynamic tiling Wayland compositor; per-workspace dwindle or scrolling layout |
| Status Bar | **Waybar** -- system monitors, weather, calendar, and indicators that only appear while something is on |
| System menu | **desktop-menu** (rofi) -- one searchable menu: capture, toggles, themes, wallpapers, tools, setup, updates, power |
| Quick settings | **SwayNC** -- toggle grid, volume (per app), brightness on laptops, media, then notifications |
| Themes | **desktop-theme** -- omarchy-format themes recolour everything at once; Dracula by default |
| Terminal | **Kitty** -- GPU-accelerated terminal (50% transparent, blurred) |
| Launcher | **Rofi** -- Spotlight-style app launcher |
| File Manager | **Thunar** -- lightweight file manager |
| Lock Screen | **hyprlock** -- themed, blurred lock (gtklock where hyprlock is unavailable) |
| Idle | **hypridle** -- screensaver at 5 min, lock at 60, screen off at 61, lock before sleep |
| Screensaver | **terminaltexteffects** -- animated banner in a fullscreen terminal |
| Night light | **hyprsunset** -- warm screen on a key or a click |
| Clipboard | **cliphist** -- clipboard history (text + images) via Rofi |
| Capture | **grim + slurp + hyprpicker** -- frozen-screen region grabs, OCR (**tesseract**), QR codes (**zbar**), colour picker, **swappy** annotation |
| Recording | **wf-recorder** -- region or screen, optional desktop/mic audio, bar indicator |
| Emoji | **rofimoji** -- emoji picker that types into the focused window |
| OSD | **SwayOSD** -- on-screen display for volume, brightness, caps lock |
| Font | **JetBrainsMono Nerd Font** |
| Wallpaper | **awww** -- animated wallpaper daemon; per-theme wallpapers plus the Donut collection from [desktop-assets](https://github.com/fursman/Desktop-Assets) |
| Laptops | Low-battery warnings, power profile per power source, clamshell mode |
| Auth prompts | **mate-polkit** -- polkit agent, so privilege prompts actually appear |
| Snapshots | **Timeshift** -- rsync system snapshots for rollback |
| Wireless display | **GNOME Network Displays** -- Miracast mirroring to a TV, see [docs/WIRELESS-DISPLAY.md](docs/WIRELESS-DISPLAY.md) |
| CapsLock (optional) | **caps-sudo** -- CapsLock arms/disarms passwordless `sudo`, LED = danger light. Opt-in, not run by `setup.sh`, see [docs/CAPS-SUDO.md](docs/CAPS-SUDO.md) |

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

Press **Super + Space** for a searchable keybind cheatsheet, **Super + Alt +
Space** for the system menu, and
**Super + N** for quick settings.

Useful flags:

```bash
./setup.sh --configs-only   # redeploy dotfiles + theme only, install nothing
./setup.sh --no-nvidia      # skip the GPU driver step
```

A `--configs-only` redeploy inside a running session re-renders the current
theme and reloads Hyprland, waybar, swaync and kitty by itself; nothing else
is needed. (Menu › Update › *Update this desktop* does `git pull` + this.)

## Setup Steps

All steps are idempotent -- each checks what is already installed and only does
the missing work, so re-running is fast and quiet.

1. **Repositories** -- adds the Hyprland PPA for the *detected* release codename,
   falling back to the archive if that series does not exist yet
2. **Packages** -- compositor, bar, launcher, portals, notification centre,
   polkit agent, toolchain; hypridle, hyprlock, hyprsunset and hyprpicker from
   the PPA; tesseract, zbar, qrencode, rofimoji, terminaltexteffects, jq
3. **Razer hardware** -- OpenRazer, only if Razer hardware is actually present
4. **NVIDIA driver** -- recommended version via `ubuntu-drivers`, signed prebuilt
   modules, then `apt-mark manual` so `autoremove` cannot orphan it
5. **Node.js 22** -- via NodeSource
6. **Fonts** -- JetBrainsMono Nerd Font v3.4.0
7. **GTK/icon theme** -- Dracula (other themes use Ubuntu's own Yaru accents)
8. **Config files** -- dotfiles, Hyprland toggles, the menu, and a
   machine-local `env-local.conf` holding GPU-specific environment
9. **Helper scripts + session wiring** -- `~/.local/bin` scripts (and a
   `~/.bashrc` line putting that directory on PATH, which Hyprland, never
   reading `~/.profile`, leaves off), then the theme is rendered into every app
   (`desktop-theme reapply`), polkit agent selection, masking `mako` so it
   cannot fight swaync for the notification bus
10. **Wallpaper daemon, assets, tuning** -- builds `awww`, pulls wallpapers and
    wlogout icons, fetches omarchy's themes, applies sysctl and NVMe scheduler
    tuning

### Why `sway-notification-center` is no longer built from source

Ubuntu 26.04 ships `sway-notification-center 0.12.4` -- the exact version this
setup used to compile by hand. The whole meson/ninja build step is gone.

## Keybinds

Press **Super + Space** to see all keybinds in a searchable Rofi menu. It is
generated from the running Hyprland: every bind in `hyprland.lua` carries a
description, so the help cannot drift from the keys. The tables below come from
the same place (`hypr-cheatsheet --markdown`). Also: `3-finger swipe` switches
workspaces, and the media/volume/brightness keys drive SwayOSD.


#### Help

| Key | Action |
|-----|--------|
| `Super + Space` | Keybinding cheatsheet |
| `Super + Alt + Space` | System menu |

#### Apps

| Key | Action |
|-----|--------|
| `Super + Enter` | App launcher |
| `Super + T` | Terminal (kitty) |
| `Super + B` | Firefox |
| `Super + Alt + B` | Chromium |
| `Super + C` | Claude |
| `Super + F` | File manager (Thunar) |
| `Super + K` | Passwords (Seahorse) |
| `Super + O` | Audio settings |
| `Super + S` | Signal |
| `Super + R` | Backups (Pika) |
| `Super + Shift + B` | System monitor (btop) |

#### Tools

| Key | Action |
|-----|--------|
| `Super + V` | Clipboard history |
| `Super + .` | Emoji picker |
| `Super + N` | Notifications & quick settings |
| `Super + Shift + N` | Do not disturb on/off |
| `Super + L` | Lock screen |
| `Super + Ctrl + L` | Screensaver now |
| `Super + X` | Power menu |

#### Capture

| Key | Action |
|-----|--------|
| `Super + Ctrl + C` | Capture menu |
| `PrtSc` | Screen → clipboard |
| `Super + F12` | Screen → ~/Pictures |
| `Super + Shift + S` | Region → clipboard |
| `Super + Shift + F12` | Region → ~/Pictures |
| `Super + Shift + A` | Region → annotate (swappy) |
| `Super + Shift + T` | Copy text from screen (OCR) |
| `Super + Shift + Q` | Read a QR code from screen |
| `Super + Shift + C` | Pick a colour |
| `Super + Shift + R` | Record region (again: stop) |
| `Super + Alt + R` | Record screen (again: stop) |

#### Windows

| Key | Action |
|-----|--------|
| `Super + Q` | Close window |
| `Super + Esc` | Fullscreen |
| `Super + Ctrl + F` | Maximize (keep gaps and bar) |
| `Super + Shift + F` | Float / tile |
| `Super + Shift + P` | Pin (always on top) |
| `Super + Alt + P` | Pop out (float, pin, centre) |
| `Super + Shift + Space` | Centre window |
| `Super + P` | Pseudo-tile |
| `Super + J` | Toggle split direction |
| `Alt + Tab` | Next window |
| `Alt + Shift + Tab` | Previous window |

#### Focus & move

| Key | Action |
|-----|--------|
| `Super + ←→↑↓` | Focus left/right/up/down |
| `Super + Shift + ←→↑↓` | Move window left/right/up/down |
| `Super + Alt + ←→↑↓` | Swap window left/right/up/down |
| `Super + Alt + Shift + ←→↑↓` | Move workspace to monitor left/right/up/down |
| `Super + Ctrl + ←` | Resize narrower |
| `Super + Ctrl + →` | Resize wider |
| `Super + Ctrl + ↑` | Resize shorter |
| `Super + Ctrl + ↓` | Resize taller |
| `Ctrl + Alt + Tab` | Focus next monitor |
| `Super + Left-drag` | Drag to move |
| `Super + Right-drag` | Drag to resize |

#### Layout

| Key | Action |
|-----|--------|
| `Super + Alt + L` | Workspace layout: dwindle ⇄ scrolling |
| `Super + Alt + =` | Scrolling: wider column |
| `Super + Alt + -` | Scrolling: narrower column |
| `Super + /` | Monitor scale up |
| `Super + Alt + /` | Monitor scale down |

#### Groups (tabs)

| Key | Action |
|-----|--------|
| `Super + G` | Group / ungroup |
| `Super + Alt + G` | Take window out of group |
| `Super + Tab` | Next tab in group |
| `Super + Shift + Tab` | Previous tab in group |

#### Workspaces

| Key | Action |
|-----|--------|
| `Super + 1…0` | Go to workspace 1–10 |
| `Super + Shift + 1…0` | Move window to workspace 1–10 |
| `Super + Alt + 1…5` | Send window to workspace 1–5 (stay) |
| `Super + Ctrl + Tab` | Back to previous workspace |
| `Super + `` | Scratchpad terminal |
| `Super + Shift + `` | Send window to scratchpad |
| `Super + Wheel down` | Next workspace (wheel) |
| `Super + Wheel up` | Previous workspace (wheel) |

#### Style

| Key | Action |
|-----|--------|
| `Super + Ctrl + T` | Pick a theme |
| `Super + Ctrl + W` | Pick a wallpaper |
| `Super + Home` | Previous wallpaper |
| `Super + End` | Next wallpaper |

#### Toggles

| Key | Action |
|-----|--------|
| `Super + Ctrl + O` | Toggles menu |
| `Super + Ctrl + N` | Night light on/off |
| `Super + Ctrl + I` | Stay awake on/off |
| `Super + Ctrl + Backspace` | Gaps on/off |
| `Super + Ctrl + A` | Single-window aspect ratio on/off |

#### Assistant

| Key | Action |
|-----|--------|
| `Super (tap)` | Voice mode on/off (tap Super) |
| `Super + Shift + V` | New conversation |
| `Super + M` | Swap model |
| `Super + A` | Conversation panel |

Two binds moved: wallpaper cycling is now **Super + Home / End** (bare
Home/End were swallowed from every app), and **Super + X** opens the menu's
Power page instead of wlogout (`wlogout` is still installed).

## The system menu

**Super + Alt + Space**. Esc goes back a level; type to
search the current page. Pages bind to keys directly: **Super + Ctrl + C**
capture, **+ O** toggles, **+ T** themes, **+ W** wallpapers, **Super + X**
power.

| Page | What's there |
|------|--------------|
| Capture | Region/screen/window to clipboard or file, annotate, OCR, QR, colour, recordings with desktop or mic audio |
| Toggles | Night light, stay awake, do not disturb, screensaver, workspace layout, no gaps, single-window aspect, no animations, solid windows, sharp corners, monitor scale |
| Style | Theme picker (previews), wallpaper picker (thumbnails), next/previous theme, fetch omarchy's themes |
| Tools | Emoji, clipboard history, reminders ("25m Tea"), calculator, web apps, btop |
| Setup | Audio, Bluetooth, network, Wi-Fi as a QR code, power profile, wireless display, edit `local.lua` / menu additions, reload |
| Update | apt, Flatpak, this repo (`git pull` + `--configs-only`), omarchy's themes |
| Power | Lock, suspend, hibernate (when available), log out, restart, shut down |

The menu is data: `~/.config/desktop-menu/menu.json`. Add your own items in
`~/.config/desktop-menu/local.json` (never overwritten) -- a menu id there adds
to that page, a new id makes a new page:

```json
{ "tools": { "items": [ { "icon": "󰊢", "label": "Lazygit", "exec": "launch-tui lazygit" } ] } }
```

## Quick settings

**Super + N** or the bell. The notification centre now opens with a toggle
grid (Wi-Fi, Bluetooth, microphone, night light, stay awake, do not disturb;
screenshot, record, theme, next wallpaper, lock, power), a volume slider with
per-app levels, a brightness slider on laptops, the media player while
something plays, and then every notification as its own card (grouping is off,
so nothing hides behind a collapsed stack).

## Themes

`desktop-theme` recolours the whole desktop at once: waybar, swaync, rofi,
kitty, Hyprland's borders, hyprlock, swayosd, btop, wlogout, gtklock and the
GTK theme/icons (Yaru accents; Dracula keeps its own).

```bash
desktop-theme list            # * marks the current one
desktop-theme set tokyo-night # or Super + Ctrl + T for the picker
desktop-theme sync            # fetch/update omarchy's ~23 themes (~280 MB, mostly wallpapers)
```

A theme is an [omarchy](https://github.com/basecamp/omarchy/tree/master/themes)
theme directory: `colors.toml` (+ optional `backgrounds/` and `icons.theme`).
Your own go in `~/.config/desktop-theme/themes/<name>/`. Themes with
wallpapers put the first one up when chosen, and **Super + Home / End** then
cycles that theme's wallpapers.

Every themed file is rendered from a template in `configs/theme/templates/`
whose first lines name its destination (`{{! dest: ~/.config/kitty/theme.conf }}`).
Placeholders are the colour names (`{{ accent }}`, `{{ background_strip }}`,
`{{ red_rgb }}`, `{{ mix background foreground 0.2 }}`, ...). To theme another
app, drop a template in `~/.config/desktop-theme/templates/` -- no code change.

## Toggles, idle and lock

- **Hyprland toggles** (`hypr-toggle <name>`, or the Toggles page): no gaps,
  single-window aspect ratio (a lone window stays 16:9 instead of stretching
  across a 32:9 panel), no animations, solid windows, sharp corners. Each is a
  Lua snippet in `configs/hypr/toggles/`; switching one on copies it into
  `~/.local/state/hypr/toggles/`, so it survives reloads, logins and redeploys.
- **Workspace layout** (**Super + Alt + L**): this workspace switches between
  dwindle and *scrolling* -- an endless strip of half-screen columns, made for
  the ultrawide. **Super + Alt + = / -** sizes the column.
- **Monitor scale** (**Super + /**, **Super + Alt + /**): steps the focused
  monitor through 1 / 1.25 / 1.33 / 1.5 / 1.6 / 2 / 2.5 / 3; persists per monitor
  until *Monitor scale reset*.
- **Night light** (**Super + Ctrl + N**), **stay awake** (**Super + Ctrl + I**):
  show on the bar only while on; click the icon to turn off.
- **Idle**: hypridle shows the screensaver after 5 minutes, locks at 60 and turns
  the screens off at 61. Video playing (players and browsers ask for it) and
  *stay awake* pause it. Replace `~/.config/screensaver/banner.txt` with your own
  art; switch the screensaver off from the Toggles page.

## Laptops

- Low battery: a notification at 20% and a critical one at 10%.
- Power profiles follow the power source: the profile you last used on AC comes
  back when you plug in (balanced at first), the battery one when you unplug
  (power-saver at first). Pick one from the bar, quick settings or Setup.
- Clamshell: closing the lid with an external monitor connected switches the
  internal panel off; opening it brings it back.
- A brightness slider appears in quick settings when the machine has a backlight.

## Waybar

The status bar shows (left to right):

- **Left**: voice assistant, workspace icons (10 persistent), taskbar
- **Center**: Active window title
- **Right**: recording pill, caps-sudo, tray, night light / stay awake / updates
  (only when relevant), network (with live bandwidth), bluetooth, disk, memory,
  CPU, temperature, audio, microphone, backlight, battery, power profile,
  weather, date (hover: month calendar), time, media player, notifications

**Click actions:**
- Workspace icon -> go to that workspace; taskbar icon -> focus that window
  (middle-click closes it)
- Network -> network settings; right-click -> nm-connection-editor
- Bluetooth -> bluetooth settings; right-click -> toggle rfkill
- Audio -> pavucontrol; right-click -> mute. Microphone -> mute; scroll -> level
- Power profile -> cycle; weather -> full forecast; updates -> Update page
- Recording pill -> stop recording
- Notification icon -> quick settings; right-click -> do not disturb

Weather comes from wttr.in, which guesses the place from your IP. Pin one with
`WEATHER_LOCATION=Vancouver` in `~/.config/desktop/env`.

## Structure

```
.
├── setup.sh                       # Desktop setup (portable)
├── gpu-passthrough.sh             # VFIO + Looking Glass + Windows VM (Blade 17)
├── caps-sudo/                     # Opt-in: CapsLock arms passwordless sudo (LED = danger light)
│   ├── install.sh / uninstall.sh
│   ├── caps-sudo                  # Root helper, run by keyd on each CapsLock press
│   ├── keyd-default.conf          # Maps CapsLock -> helper
│   └── caps-sudo-disarm-on-boot.service
├── docs/
│   ├── GPU-PASSTHROUGH.md         # Why every passthrough knob exists
│   ├── WIRELESS-DISPLAY.md        # Miracast: the protocol and the 3 gotchas
│   └── CAPS-SUDO.md               # CapsLock passwordless-sudo toggle, and its sharp edges
├── configs/
│   ├── theme/templates/*.tpl      # Every themed file: palette.css, kitty, rofi, hypr, btop, ...
│   ├── hypr/hyprland.lua          # Compositor (loads env-local, polkit-local, theme, state, local)
│   ├── hypr/hyprland.conf         # Old hyprlang config, rollback only (not updated)
│   ├── hypr/toggles/*.lua         # Optional looks, switched with hypr-toggle
│   ├── hypr/{hypridle,hyprlock}.conf
│   ├── desktop-menu/menu.json     # The system menu's tree
│   ├── screensaver/banner.txt     # Seeded once; replace with your own art
│   ├── waybar/{config.jsonc,style.css}   # Deployed as base.jsonc; config.jsonc is the local override stub
│   ├── kitty/kitty.conf
│   ├── rofi/{config.rasi,spotlight-dark.rasi}
│   ├── mako/config
│   ├── swaync/{config.json,style.css}
│   ├── wlogout/{layout,style.css}
│   └── gtklock/style.css
├── llm-serve/                     # Opt-in: Qwen3.8-27B on one 24GB GPU (llama.cpp + MTP)
│   ├── install.sh                 # CUDA build (all present GPU archs), model download, unit
│   ├── qwen38.service             # Measured flags; why 192K ctx, q4 KV, draft-n-max 2
│   └── README.md                  # Why not vLLM on Ada, the numbers, the gotchas
├── passthrough/                   # Verbatim artifacts from the live host
│   ├── hosts/block/               # Desktop variant (i9 + 4090): no laptop hacks, pinned kernel
│   ├── grub.d/40_gpu-passthrough  # Generates the second boot entry
│   ├── modprobe.d/{vfio,kvmfr}.conf
│   ├── modules-load.d/kvmfr.conf
│   ├── sysctl.d/99-hugepages.conf
│   ├── udev/*.rules               # kvmfr perms, 8BitDo, governor, USB wake
│   ├── acpi/ssdt-battery.asl      # Fake battery (recompilable source)
│   ├── vm/win10-lg.xml            # libvirt domain
│   ├── bin/{lg-start,lg-stop,8bitdo-passthrough,dump-vbios.sh}
│   └── assets/                    # vBIOS lives here, gitignored
├── themes/dracula/colors.toml     # The default theme, in omarchy's format
└── scripts/                       # Installed to ~/.local/bin
    ├── desktop-menu             # The system menu (rofi, data from menu.json + local.json)
    ├── desktop-theme            # Theme engine: list/set/next/sync, renders the templates
    ├── quick-settings           # Backend for the swaync toggle buttons
    ├── capture / screenrecord   # Screenshots, OCR, QR, colour; recording + bar pill
    ├── nightlight / stay-awake  # hyprsunset; systemd idle inhibitor
    ├── hypr-toggle              # Optional looks (gaps, aspect, animations, ...)
    ├── workspace-layout         # dwindle <-> scrolling, per workspace
    ├── monitor-scale            # Super + / scale stepping
    ├── window-pop               # Float + pin + centre, and back
    ├── screensaver(-run)        # hypridle's screensaver
    ├── power-monitor            # Battery warnings, power profile per power source
    ├── lid-switch               # Clamshell mode
    ├── wallpaper-set            # Set + remember the wallpaper
    ├── bar-status               # Waybar: date + calendar, weather, updates
    ├── emoji-picker, reminder, webapp-install, wifi-qr, launch-tui
    ├── lock-screen
    ├── wireless-display
    ├── keyboard-fire            # Razer per-key RGB flame effect (openrazer)
    ├── keyboard-ambient         # Calm warm-white backlight + red CapsLock key while caps-sudo is armed
    ├── hypr-cheatsheet
    ├── restart-waybar
    ├── waybar-launch            # Login autostart: restarts waybar after a crash, logs to ~/.local/state/waybar/
    ├── wallpaper-cycle
    ├── open-network-settings
    └── open-bluetooth-settings
```

## Theming conventions

Every GTK-CSS surface -- waybar, swaync, wlogout, gtklock -- imports a
`palette.css` that `desktop-theme` renders next to it (GTK CSS has no `~`
expansion or import path). Stylesheets use role names -- `@accent`, `@bg`,
`@fg`, `@muted`, `@surface`, `@on-accent` -- plus the hues (`@red`, `@cyan`,
...); the old Dracula names (`@purple`, `@comment`, `@current`) remain as
aliases.

Two conventions keep it coherent on every theme:

- **Accents carry meaning.** A module is coloured by its domain (connectivity
  cyan, compute accent, power green, brightness yellow), softened towards the
  text colour, and only shifts to orange/red when it wants attention.
- **One radius, one gap.** Every pill is `10px` with a `5px` vertical margin, so
  bar height stays uniform regardless of which modules are enabled.

### A note on sizing

The reference machine is a 17" 3840x2160 panel running at **scale 1.0** (~257
DPI), so type in the stylesheets is specified deliberately large (19-26px). If
you set a monitor scale in `hyprland.lua`, divide every px value in the
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

- **Colours**: `desktop-theme set <name>`, or your own theme in
  `~/.config/desktop-theme/themes/<name>/colors.toml`
- **Wallpaper**: Super + Ctrl + W picks one; Super + Home / End cycles. Add
  images to `~/Pictures/Wallpapers` (used when the theme ships none)
- **Menu**: `~/.config/desktop-menu/local.json` (never overwritten)
- **Machine-local Hyprland**: `~/.config/hypr/local.lua` (never overwritten)
- **GPU config**: `~/.config/hypr/env-local.conf` (never overwritten by redeploys)
- **Keybinds**: `~/.config/hypr/hyprland.lua`, then `hyprctl reload`
- **Waybar modules**: `~/.config/waybar/base.jsonc` is the deployed config; put
  machine-local overrides in `~/.config/waybar/config.jsonc` (never overwritten,
  wins option by option), then `pkill -SIGUSR2 waybar`

## Credits

- [Hyprland](https://hyprland.org/) -- Wayland compositor
- [omarchy](https://github.com/basecamp/omarchy) (MIT) -- the model for the menu,
  quick settings, toggles, capture tools, screensaver and theme format; its
  themes are fetched as-is by `desktop-theme sync`
- [Dracula Theme](https://draculatheme.com/) -- GTK theme & icons
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/) -- Typeface
- [Nerd Fonts](https://www.nerdfonts.com/) -- Patched fonts with icons
- [fursman/Desktop-Assets](https://github.com/fursman/Desktop-Assets) -- Wallpapers & wlogout icons

## License

MIT
