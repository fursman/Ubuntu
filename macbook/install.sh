#!/usr/bin/env bash
# MacBook Pro (Cirrus CS8409 codec) audio quirk: never let PipeWire suspend the
# analog device, because closing the playback side freezes the capture side.
# See README.md in this directory for the evidence.
#
#     ./install.sh            for this user  (~/.config/wireplumber, no sudo)
#     sudo ./install.sh --system   for every user (/etc/wireplumber)
#     ./install.sh --remove   undo (same scope rules)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RULE="51-cs8409-no-suspend.conf"
SCOPE=user; REMOVE=0
for a in "$@"; do
  case "$a" in
    --system) SCOPE=system ;;
    --user)   SCOPE=user ;;
    --remove) REMOVE=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

if [ "$SCOPE" = system ]; then
  [ "$EUID" -eq 0 ] || { echo "--system needs root: sudo ./install.sh --system" >&2; exit 1; }
  DEST=/etc/wireplumber/wireplumber.conf.d
  RESTART_AS="${SUDO_USER:-}"
else
  [ "$EUID" -ne 0 ] || { echo "run without sudo for a per-user install (or pass --system)" >&2; exit 1; }
  DEST="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
  RESTART_AS=""
fi

# Only meaningful on this codec. The rule itself also matches on it, so an
# install elsewhere is harmless, just pointless.
if ! grep -qs 'Vendor Id: 0x10138409' /proc/asound/card*/codec#* 2>/dev/null; then
  echo "!! no Cirrus CS8409 codec found on this machine; installing anyway (the rule matches on the codec id)"
fi

if [ "$REMOVE" = 1 ]; then
  if [ -f "$DEST/$RULE" ]; then
    rm -f "$DEST/$RULE"; echo ">> removed $DEST/$RULE"
  else
    echo ">> $DEST/$RULE was not installed"
  fi
else
  install -d -m 0755 "$DEST"
  if cmp -s "$DIR/wireplumber/$RULE" "$DEST/$RULE"; then
    echo ">> $DEST/$RULE already up to date"
  else
    install -m 0644 "$DIR/wireplumber/$RULE" "$DEST/$RULE"
    echo ">> installed $DEST/$RULE"
  fi
fi

# WirePlumber reads its configuration at start, so restart the user's instance.
# Anything that is playing at that moment will hiccup for a second.
restart() {
  if [ -n "$RESTART_AS" ]; then
    uid=$(id -u "$RESTART_AS")
    runuser -u "$RESTART_AS" -- env "XDG_RUNTIME_DIR=/run/user/$uid" \
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" \
      systemctl --user restart wireplumber.service
  else
    systemctl --user restart wireplumber.service
  fi
}
if restart 2>/dev/null; then
  echo ">> wireplumber restarted"
else
  echo "!! could not restart wireplumber; log out and in, or run: systemctl --user restart wireplumber"
fi
