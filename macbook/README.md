# MacBook Pro -- keep the sound card awake, or the microphone dies

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

```bash
./install.sh              # this user only  (~/.config/wireplumber, no sudo)
sudo ./install.sh --system   # every user     (/etc/wireplumber)
./install.sh --remove     # undo
```

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

## Related

The voice assistant ([fursman/Assistant](https://github.com/fursman/Assistant))
also protects itself, by holding its playback stream open for as long as it is
listening. Both are worth having: the assistant works on a machine without this
rule, and this rule protects every other recorder on this machine.
