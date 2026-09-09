# MacBook Pro -- the quirks this machine needs

Two small, hardware-specific fixes for a MacBook Pro running Ubuntu. They are
independent, both are inert on other hardware, and both are here for the same
reason: the symptom looked nothing like the cause.

Tested on a **MacBookPro14,1** (2017 13-inch, Kaby Lake), but neither fix is
tied to that model -- one matches on an audio codec id, the other on an input
device name.

```bash
./install.sh                 # audio fix, this user only (~/.config/wireplumber, no sudo)
sudo ./install.sh --system   # both fixes, system-wide
./install.sh --remove        # undo (same scope rules)
./install.sh --audio         # only one of them
sudo ./install.sh --input    # ditto
```

The input fix always needs root: libinput reads exactly one local file,
`/etc/libinput/local-overrides.quirks`, and there is no per-user equivalent.

---

# 1. Palm rejection does nothing, because the keyboard has no vendor ID

The trackpad clicks and jumps constantly while you type. Every desktop reports
"disable while typing" as **on**. Turning it off and on again changes nothing,
because it was never running.

## Why

libinput only suppresses a touchpad while you type when it can **pair** that
touchpad with a keyboard tagged *internal*. An external keyboard should not
silence your trackpad, so the pairing is deliberate and the tag is the gate.

libinput ships a rule for precisely this keyboard:

```
[Apple Internal Keyboard (SPI)]
MatchUdevType=keyboard
MatchBus=spi
MatchVendor=0x05AC
AttrKeyboardIntegration=internal
```

But the `applespi` driver does not report Apple's vendor id. It reports no
vendor at all:

```
$ grep -B4 'applespi/input0' /proc/bus/input/devices | grep -E '^I:|^N:'
I: Bus=001c Vendor=0000 Product=0000 Version=0000
N: Name="Apple SPI Keyboard"
```

`0x0000` is not `0x05AC`, so the rule never matches, the keyboard is never
tagged internal, no pairing happens, and disable-while-typing silently does
nothing. Nothing logs a warning; the feature simply has no keyboard to watch.

The same driver's *other* half was already worked around upstream. The touchpad
reports the **Synaptics** vendor `0x06cb`, and libinput carries a second quirk
for it with a comment saying so:

```
# The Linux applespi driver currently uses the Synaptics vendor for some reason
[Apple Laptop Touchpad (SPI) applespi driver]
MatchVendor=0x06CB
...
```

The keyboard half was missed. This is worth reporting upstream -- it affects
every applespi MacBook.

## It is not a tuning problem

Worth ruling out, because the obvious next move is to start moving thresholds.
The touchpad's shipped tuning is fine:

| | |
|---|---|
| contact size axis (`ABS_MT_TOUCH_MAJOR`) | 0 – 5000 |
| `AttrPalmSizeThreshold` from the shipped quirk | 1600, about a third of scale |
| geometry libinput derives | 135 x 84 mm, correct |

Nothing there needed changing. The palm-size machinery was correct and simply
never got the chance to run.

## The fix

`libinput/applespi-keyboard-integration.quirks` matches the keyboard **by
name**, which is stable and unique to this driver, and tags it internal:

```
[Apple SPI Keyboard (applespi, reports vendor 0000)]
MatchUdevType=keyboard
MatchBus=spi
MatchName=Apple SPI Keyboard
AttrKeyboardIntegration=internal
```

`install.sh --input` merges that into `/etc/libinput/local-overrides.quirks` as
a marked block, so it coexists with anything already in the file and `--remove`
takes back exactly what it added.

**Log out and back in afterwards.** There is no reload path: libinput reads
quirks when a device joins its context, and the compositor built its context at
login.

## Verifying

```bash
sudo libinput quirks list /dev/input/event4   # the Apple SPI Keyboard
```

Before the fix this prints nothing. After it:

```
AttrKeyboardIntegration=internal
```

Check the event number first, since it is not fixed:

```bash
grep -B6 'applespi/input0' /proc/bus/input/devices | grep -E '^N:|Handlers'
```

The touchpad, for contrast, was always getting its quirks:

```bash
sudo libinput quirks list /dev/input/event5
ModelAppleTouchpad=1
AttrSizeHint=104x75
AttrPalmSizeThreshold=1600
AttrTouchSizeRange=150:130
```

## Worth pairing with

This trackpad is large and your palms rest on it. Even with disable-while-typing
working, a tap that lands during a pause is still a click. Two settings make the
damage smaller:

- **`tap-and-drag`** turns a stray tap into a *drag*, which scrambles text rather
  than just moving the cursor. `configs/hypr/hyprland.conf` enables it in the
  `touchpad` block; set it to `false` on this hardware.
- **`tap-to-click`** off entirely is the belt-and-braces answer. The Force Touch
  trackpad has an excellent physical click, and a resting palm cannot trigger it.

---

# 2. Keep the sound card awake, or the microphone dies

On the MacBook Pro 14,1 (Cirrus **CS8409** HDA codec with the CS42L83
companion, `snd_hda_intel` with `power_save=1`), **closing the playback side of
the card freezes the capture side.** Whatever was recording keeps its stream:
ALSA still says it is running, PipeWire still reports the source `RUNNING`, no
xrun, no error. The samples just stop.

PipeWire suspends an idle sink 5 s after its last stream closes, so the
failure looks like this from any app that records without also playing:

```
t= 1s callbacks= 28  sink=IDLE       source=RUNNING     <- a 1 s chime just finished
t= 4s callbacks= 17  sink=IDLE       source=RUNNING
t= 5s callbacks= 13  sink=SUSPENDED  source=RUNNING     <- WirePlumber suspends the sink
t= 6s callbacks=  0  sink=SUSPENDED  source=RUNNING     <- capture is dead
t=18s callbacks=  0  sink=SUSPENDED  source=RUNNING
```

(Bare PortAudio capture stream, measured 2026-09-06. It reproduced to the
second every time; with a silent output stream held open, or with the rule
below, the callbacks never stop and the sink stays `IDLE`.)

A voice call is immune because its playback stream is always open. A voice
assistant, a dictation tool, or anything else that listens in silence is not:
its first long recording after any sound ends loses everything past the
five-second mark, and the stream never recovers on its own.

## The fix

`wireplumber/51-cs8409-no-suspend.conf` tells WirePlumber never to suspend the
analog nodes of this codec:

```
session.suspend-timeout-seconds = 0
```

It matches on `alsa.components` containing the codec id `HDA:10138409`, not on
a PCI path, so it does nothing on any other machine. The sink then idles
instead of suspending, which keeps the playback PCM open and the codec
powered. The cost is the runtime power saving on the codec while nothing is
playing; the DKMS driver this machine needs was never good at that anyway.

WirePlumber runs per user and reads its configuration at start, so the
installer restarts it; audio hiccups for a second.

## Verifying

Start something recording, play a short sound, and watch the sink for ten
seconds:

```bash
pw-play /usr/share/sounds/freedesktop/stereo/bell.oga
watch -n1 'pactl list sinks short | grep analog'
```

Without the rule it goes `IDLE` -> `SUSPENDED` at five seconds and the recorder
falls silent. With it, it stays `IDLE`.

---

## Related

The voice assistant ([fursman/Assistant](https://github.com/fursman/Assistant))
also protects itself from the audio quirk, by holding its playback stream open
for as long as it is listening. Both are worth having: the assistant works on a
machine without this rule, and this rule protects every other recorder on this
machine.
