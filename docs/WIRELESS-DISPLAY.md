# Wireless display (Miracast) from Hyprland

Mirroring the laptop screen to a TV over Wi-Fi Direct, with no dongle and no
cable. Verified working to a Samsung **"The Movingstyle"** (`UN27LSM7FAXXZC`,
Tizen, 2560x1440) on 2026-08-23: `ND_SINK_STATE_STREAMING`, ~2 Mbit/s of H.264.

Installed by `setup.sh`. This document is the part you cannot infer from the
config: which protocol actually works, and the three things that silently stop
it working.

---

## Which protocol, and why it matters

The TV advertises three receivers at once:

| Service | Port | Usable from Linux? |
|---|---|---|
| AirPlay 3.6 | 7000 | No practical Linux sender |
| Google Cast | 8008/8009 | Casts *media URLs*, cannot mirror a Wayland desktop |
| **Wi-Fi Display (Miracast)** | **7236** | **Yes — this is the one** |

Miracast is the only one that mirrors an arbitrary desktop. Confirm a TV really
supports it by decoding the Wi-Fi Display information elements in its beacon:

```
01 11 | 1C 44 | 00 36
        ^^ ^^
        device type 0b01 = Primary Sink, available for session
                     control port 0x1C44 = 7236
```

A set that shows those IEs is a real Miracast sink regardless of what the
vendor documents.

The sender is the **`org.gnome.NetworkDisplays` flatpak** (GNOME Network
Displays). It speaks WFD/RTSP and drives NetworkManager's Wi-Fi P2P support.

---

## The three gotchas

### 1. The firewall is the real blocker, and the direction is backwards

This is the one that costs an afternoon. Intuition says the laptop dials out to
the TV. It does not:

> **GNOME Network Displays runs the RTSP *server*. The TV connects *in* to
> port 7236 on the laptop.**

So a default-deny-incoming firewall kills it, with no useful error — the sink
just never leaves "connecting".

Worse, GND can only auto-open ports through **firewalld**, which is not
installed here. It logs:

```
Firewalld does not seem to be installed
```

and then carries on as if the ports were open. The rules must be added by hand:

```bash
sudo ufw allow 7236/tcp comment 'Miracast RTSP (gnome-network-displays)'
sudo ufw allow 7236/udp comment 'Miracast RTSP/UDP'
sudo ufw allow 5353/udp comment 'mDNS discovery'
```

These persist across reboots. `setup.sh` adds them when `ufw` is active.

### 2. The TV appears twice — pick the right one

GND lists the same set under two names:

| Entry | Protocol | Use it? |
|---|---|---|
| `The Movingstyle - LSM7F` | Google Cast | No |
| `The Movingstyle` (plain) | Miracast / WFD | **Yes** |

Pick the **plain** name, without the model suffix. The list also reorders as
mDNS entries churn, so match by name rather than by position.

### 3. The portal prompt comes at startup, not on connect

GND raises the xdg-desktop-portal screencast picker the moment it launches,
before you have chosen a sink. It has to be answered before streaming can
start, and it is easy to miss because nothing has visibly happened yet.

Under Hyprland, `input:follow_mouse = 1` means `hyprctl dispatch focuswindow`
will not actually focus the picker — move the cursor into it first:

```bash
hyprctl dispatch movecursor <x> <y>
```

---

## Using it

```bash
wireless-display          # helper installed by setup.sh
```

or launch **Network Displays** from the launcher and click the plain
`The Movingstyle` entry.

## What a working session looks like

```
P2P group     DIRECT-NX, channel 149
Laptop        10.42.0.1/24   (p2p-wlp62s0-1)
TV            10.42.0.218
Encoder       x264enc + avenc_aac + mpegtsmux   (software H.264)
Negotiated    1920x1080@30
```

Channel 149 is the same channel as the normal Wi-Fi association, so the AX210's
dual-channel concurrency is not stressed and the regular connection is
unaffected.

## Known limitations

- **Resolution caps at 1080p30.** GND logs *"No resolution found, falling back
  to standard FullHD"* rather than negotiating the panel's 3840x2160 or the
  TV's 2560x1440. This is a GND limitation, not a hardware one.
- **RTSP keep-alive gets disabled** after GND detects an RTCP port quirk. If a
  long session drops unexpectedly, look here first.
- **Encoding is software x264.** The flatpak carries nvcodec/NVENC but GND did
  not select it. Expect a core or two of CPU load while streaming.
- **The TV only answers when awake.** A ping sweep while it is in standby finds
  nothing; its AirPlay (7000) and Samsung API (8001/8002) ports are likewise
  only up when the set is on.

## Debugging

```bash
# Is the P2P group up?
ip -br addr | grep p2p

# Is the firewall actually allowing 7236?
sudo ufw status verbose | grep 7236

# GND's own log — the sink state machine is verbose and useful
flatpak run org.gnome.NetworkDisplays
```

Watch for `ND_SINK_STATE_STREAMING`. Anything stuck earlier than that, with the
firewall rules present, is usually the unanswered portal prompt.

Note: `pgrep -f <name>` matches its own shell command line and will report a
false positive for itself. Use `pgrep -x`, or exclude the current PID.
