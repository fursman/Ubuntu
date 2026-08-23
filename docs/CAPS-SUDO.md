# caps-sudo -- CapsLock as a passwordless-sudo arm switch

Turns the **CapsLock key** into an arm/disarm toggle for passwordless `sudo`, and
turns the **physical CapsLock LED** into the danger light: lit means passwordless
`sudo` is live.

> **Read this whole page before installing.** While armed, *any* process that runs
> `sudo` gets root with no password -- not only you at the keyboard. This is a
> deliberate, sharp-edged convenience. `setup.sh` never touches it.

## What you get

- **Tap CapsLock while disarmed** -> a small terminal appears and asks for your
  password. Authenticate -> passwordless `sudo` turns on, the CapsLock LED lights.
- **Tap CapsLock while armed** -> disarms instantly, no prompt, LED off.

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
| LED path is globbed `*/sys/class/leds/*capslock*/brightness*` | The input device index (e.g. `input9::capslock`) changes across reboots and reconnects; the glob follows it. |

## Behaviour choices baked in

- **No auto-timeout.** Armed until you tap CapsLock again (within a session). The
  boot-disarm unit is the only automatic revert.
- **Whole-keyboard scope.** keyd's `[ids] *` binds every keyboard's CapsLock.

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
