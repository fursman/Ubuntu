#!/usr/bin/env bash
# MacBook Pro hardware quirks. Two independent fixes, see README.md for the
# evidence behind each:
#
#   audio  Cirrus CS8409 codec: never let PipeWire suspend the analog device,
#          because closing the playback side freezes the capture side.
#   input  The applespi keyboard reports vendor 0000, so libinput never tags it
#          internal, never pairs it with the touchpad, and disable-while-typing
#          silently does nothing. Palm rejection looks absent rather than weak.
#
# The audio fix can be per-user. The input fix cannot: libinput reads exactly
# one local file, /etc/libinput/local-overrides.quirks, so it always needs root.
#
#     ./install.sh                 audio fix for this user (~/.config/wireplumber)
#     sudo ./install.sh --system   both fixes, system-wide
#     ./install.sh --remove        undo (same scope rules)
#     --audio / --input            do only one of them
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RULE="51-cs8409-no-suspend.conf"
QUIRK_SRC="$DIR/libinput/applespi-keyboard-integration.quirks"
QUIRK_DEST=/etc/libinput/local-overrides.quirks
MARK_BEGIN="# >>> fursman/Ubuntu macbook: applespi keyboard integration >>>"
MARK_END="# <<< fursman/Ubuntu macbook: applespi keyboard integration <<<"

SCOPE=user; REMOVE=0; DO_AUDIO=1; DO_INPUT=1; PICKED=0
for a in "$@"; do
  case "$a" in
    --system) SCOPE=system ;;
    --user)   SCOPE=user ;;
    --remove) REMOVE=1 ;;
    --audio)  DO_AUDIO=1; DO_INPUT=0; PICKED=1 ;;
    --input)  DO_INPUT=1; DO_AUDIO=0; PICKED=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
[ "$PICKED" = 1 ] || true

if [ "$SCOPE" = system ]; then
  [ "$EUID" -eq 0 ] || { echo "--system needs root: sudo ./install.sh --system" >&2; exit 1; }
  DEST=/etc/wireplumber/wireplumber.conf.d
  RESTART_AS="${SUDO_USER:-}"
else
  [ "$EUID" -ne 0 ] || { echo "run without sudo for a per-user install (or pass --system)" >&2; exit 1; }
  DEST="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
  RESTART_AS=""
fi

# ---------------------------------------------------------------- audio ----
audio() {
  # Only meaningful on this codec. The rule itself also matches on it, so an
  # install elsewhere is harmless, just pointless.
  if ! grep -qs 'Vendor Id: 0x10138409' /proc/asound/card*/codec#* 2>/dev/null; then
    echo "!! no Cirrus CS8409 codec found; installing anyway (the rule matches on the codec id)"
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

  # WirePlumber reads its configuration at start, so restart the user's
  # instance. Anything playing at that moment hiccups for a second.
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
}

# ---------------------------------------------------------------- input ----
# libinput reads one local file, so this merges a marked block into it rather
# than dropping a file of its own. Idempotent, and --remove takes back exactly
# what was added.
# Drops our marked block, and also any earlier unmarked copy of the section
# (a hand-installed one, from before this installer existed). A quirks section
# runs from its [Header] line to the next [ or to EOF.
SECTION="$(grep -m1 '^\[' "$QUIRK_SRC")"
strip_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v s="$SECTION" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    skip  {next}
    $0==s {insec=1; next}
    insec && /^\[/ {insec=0}
    !insec {print}
  ' "$1"
}

input() {
  if [ "$EUID" -ne 0 ]; then
    echo "!! the input fix needs root (libinput only reads $QUIRK_DEST)"
    echo "   run: sudo $0 --input"
    return 0
  fi
  if ! grep -qs 'Apple SPI Keyboard' /proc/bus/input/devices; then
    echo "!! no 'Apple SPI Keyboard' on this machine; installing anyway (the rule matches on that name)"
  fi

  local tmp; tmp=$(mktemp)
  [ -f "$QUIRK_DEST" ] && strip_block "$QUIRK_DEST" > "$tmp"

  if [ "$REMOVE" = 1 ]; then
    if [ ! -f "$QUIRK_DEST" ] || ! grep -qsF "$MARK_BEGIN" "$QUIRK_DEST"; then
      echo ">> the libinput block was not installed"
    elif [ -s "$tmp" ] && grep -qv '^[[:space:]]*$' "$tmp"; then
      install -m 0644 "$tmp" "$QUIRK_DEST"; echo ">> removed the block from $QUIRK_DEST"
    else
      rm -f "$QUIRK_DEST"; echo ">> removed $QUIRK_DEST (nothing else was in it)"
    fi
  else
    { cat "$tmp"; echo "$MARK_BEGIN"; cat "$QUIRK_SRC"; echo "$MARK_END"; } > "$tmp.new"
    install -d -m 0755 /etc/libinput
    if cmp -s "$tmp.new" "$QUIRK_DEST"; then
      echo ">> $QUIRK_DEST already up to date"
    else
      install -m 0644 "$tmp.new" "$QUIRK_DEST"
      echo ">> installed the block into $QUIRK_DEST"
    fi
    rm -f "$tmp.new"
    # There is no reload: libinput reads quirks when a device joins its
    # context, and the compositor's context was built at login.
    echo ">> log out and back in for this to take effect"
  fi
  rm -f "$tmp"
}

[ "$DO_AUDIO" = 1 ] && audio
[ "$DO_INPUT" = 1 ] && input
exit 0
