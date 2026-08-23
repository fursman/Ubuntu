# caps-sudo -- CapsLock as a passwordless-sudo arm switch

Turns the **CapsLock key** into an arm/disarm toggle for passwordless `sudo`, and
turns the **physical CapsLock LED** into the danger light: lit means passwordless
`sudo` is live.

> **Read this whole page before installing.** While armed, *any* process that runs
> `sudo` gets root with no password -- not only you at the keyboard. This is a
> deliberate, sharp-edged convenience. `setup.sh` never touches it.

## What you get

- **Tap CapsLock while disarmed** -> your desktop's **native authentication
  dialog** appears. Authenticate -> passwordless `sudo` turns on, the CapsLock
  LED lights, and an on-screen indicator appears.
- **Tap CapsLock while armed** -> disarms instantly, no prompt, LED off,
  indicator gone.

Authentication is required only to *arm*. Disarming drops a privilege, so it never
asks.

## Install

Needs `keyd`, so it can't run while a release upgrade holds the dpkg lock.

```
sudo caps-sudo/install.sh      # from the repo root
```

Start disarmed. Tap CapsLock to try it. Remove with `sudo caps-sudo/uninstall.sh`.

## Why each piece exists

| Piece | Why |
|---|---|
| **keyd** remaps CapsLock at the evdev layer to `command(...)` | It both fires the toggle *and* stops CapsLock from driving xkb's lock state. That second part is what frees the LED for us -- otherwise the lock state and our LED writes would fight. CapsLock stops type-locking entirely, which is the point. |
| Armed == `/etc/sudoers.d/90-caps-armed` (`NOPASSWD:ALL`) | Presence of one file *is* the state. Nothing to get out of sync. |
| Every write goes through `visudo -cf` before `mv` into place | A malformed sudoers file breaks `sudo` for the whole system. We validate a temp copy first and only move it in if it parses. A typo can never lock you out. |
| Arming pops a terminal running `sudo -k; sudo caps-sudo arm-commit` | `sudo -k` clears any cached grant so the prompt is always fresh; the `sudo` call itself is the authentication and runs the privileged commit as root. No separate polkit action, no pre-seeded NOPASSWD entry needed to bootstrap. |
| `caps-sudo-disarm-on-boot.service` force-disarms at every boot | sudoers drop-ins survive reboots. Without this, an armed machine that rebooted would come back up silently rooted. The unit guarantees every boot starts disarmed. |
| LED path is globbed `*/sys/class/leds/*capslock*/brightness*` | The input device index (e.g. `input9::capslock`) changes across reboots and reconnects; the glob follows it. Note keyd's own virtual keyboard also exposes a `*capslock*` node with no hardware behind it, so the glob can match phantoms -- `led_set` reads back to see whether any real LED held the value. |
| Authentication goes through **polkit**, and the helper drops to `$TARGET_USER` before calling `pkexec` | keyd runs the helper as root, and polkit authorises a root caller unconditionally -- calling `pkexec` directly from the helper would arm the machine **with no prompt at all**. Dropping privileges first is what makes polkit demand a password. |
| The action is `auth_admin`, never `auth_admin_keep` | `_keep` caches the authorisation for minutes, which would let a second arm skip the prompt. Every arm must cost a fresh password. |
| The on-screen indicator is **additive**, not a replacement for the LED | The LED is the best signal when you are looking at the keyboard, but it is invisible when you are not -- and some laptop keyboard drivers ignore brightness writes entirely. Run `sudo caps-sudo led-test` to find out which kind you have. |

## Behaviour choices baked in

- **No auto-timeout.** Armed until you tap CapsLock again (within a session). The
  boot-disarm unit is the only automatic revert.
- **Whole-keyboard scope.** keyd's `[ids] *` binds every keyboard's CapsLock.

## On-screen indicator

The LED is the primary light. The on-screen indicator is additive, so you get a
signal whether or not you are looking at the keyboard.

- **GNOME**: `install.sh` drops a shell extension into your home and pre-enables
  it. GNOME cannot hot-load a new extension on Wayland, so **log out and back in
  once**; after that it appears and disappears with the armed state. It renders
  as a red pill in the top bar, deliberately echoing GNOME's own
  screen-recording indicator, and clicking it disarms.
- **waybar / Hyprland**: add the module and CSS from
  `caps-sudo/indicator/waybar/` to `configs/waybar/`. `caps-sudo waybar` streams
  one JSON line per state change and runs unprivileged -- `/etc/sudoers.d` is
  world-listable, so testing whether the armed file *exists* needs no privilege,
  and its root-only contents are never read.

## If your session has no polkit agent

Bare window managers may not run one. Set `CAPS_SUDO_AUTH=terminal` and
caps-sudo falls back to the original behaviour: a terminal where `sudo` itself
does the asking.

It uses the first of these it finds, so you are not required to install kitty
on a machine that does not already have it:

`kitty`, `alacritty`, `foot`, `ptyxis`, `gnome-terminal`, `konsole`, `xterm`

`install.sh` prints which authentication path your machine will actually use,
and warns loudly if *neither* is available -- a CapsLock tap that silently does
nothing is the worst possible failure mode for a security toggle.

## Razer keyboards: light the CapsLock *key*, not the LED

On the Hyprland/Blade target the HID CapsLock LED is a dead end: keyd owns it
and forces it off continuously (a re-assert loop reads back 0 even
immediately after every write). But the keyboard is per-key RGB via openrazer,
which keyd knows nothing about -- so `scripts/keyboard-ambient` paints a calm
warm-white backlight and turns the **CapsLock key itself max red** while armed.
It replaces `keyboard-fire` (only one process may own the key matrix; the unit
declares `Conflicts=` on it):

```
install -m 0644 caps-sudo/indicator/razer/keyboard-ambient.service ~/.config/systemd/user/
systemctl --user disable --now keyboard-fire.service
systemctl --user enable --now keyboard-ambient.service
```

The keyboard's global dimmer stays at 100 so the red key can hit full
brightness; the calm look comes from the ambient colour being low. If your
CapsLock is not at matrix (3,1), set `KEYBOARD_CAPS_POS=row,col` in the unit.

## Does your CapsLock LED actually work?

```
sudo caps-sudo led-test
```

It lights the LED, reads the value back, and tells you whether the hardware
honoured it. A write that returns no error is *not* proof the light changed --
some drivers accept and silently discard it.

## Verify the LED after install

```
sudo caps-sudo/caps-sudo arm-commit   # LED should light
sudo caps-sudo/caps-sudo disarm       # LED should go dark
```

If it doesn't respond, check `ls /sys/class/leds/*capslock*` -- some keyboards
expose the indicator under a different name.

## Optional: float the prompt window

In `configs/hypr/hyprland.conf`:

```
windowrulev2 = float, class:^(caps-sudo-auth)$
```
