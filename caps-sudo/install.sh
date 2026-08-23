#!/usr/bin/env bash
# Install caps-sudo. Run AFTER the 26.04 upgrade finishes (needs the dpkg lock free):
#     sudo ./install.sh
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "run with sudo: sudo ./install.sh" >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
OWNER="${SUDO_USER:-user}"          # the graphical-session user this arms for
[ "$OWNER" != "root" ] || { echo "run via sudo as your normal user, not root login" >&2; exit 1; }

echo ">> target user: $OWNER"

# 1. keyd (evdev remapper; cleanly kills CapsLock's lock behaviour)
if ! command -v keyd >/dev/null 2>&1; then
  echo ">> installing keyd"
  apt-get update && apt-get install -y keyd
fi

# 2. the helper, with the target user baked in
echo ">> installing /usr/local/sbin/caps-sudo"
sed "s/__TARGET_USER__/$OWNER/" "$DIR/caps-sudo" >/usr/local/sbin/caps-sudo
chown root:root /usr/local/sbin/caps-sudo
chmod 0755      /usr/local/sbin/caps-sudo

# 3. keyd config (do not clobber an existing one)
install -d /etc/keyd
if [ -f /etc/keyd/default.conf ]; then
  if grep -q 'caps-sudo keypress' /etc/keyd/default.conf; then
    echo ">> keyd config already wired"
  else
    echo "!! /etc/keyd/default.conf exists — add this line under [main] yourself:"
    echo "     capslock = command(/usr/local/sbin/caps-sudo keypress)"
  fi
else
  install -m 0644 "$DIR/keyd-default.conf" /etc/keyd/default.conf
fi

# 4. boot-time safety disarm (armed state never survives a reboot)
install -m 0644 "$DIR/caps-sudo-disarm-on-boot.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable caps-sudo-disarm-on-boot.service

# 5. start keyd
systemctl enable --now keyd
keyd reload 2>/dev/null || systemctl restart keyd

echo
echo ">> done. Start disarmed. Tap CapsLock:"
echo "     - a terminal appears asking for your password  -> arms (LED lights)"
echo "     - tap again                                    -> disarms instantly (LED off)"
echo ">> verify the LED responds:  sudo /usr/local/sbin/caps-sudo arm-commit; sleep 2; sudo /usr/local/sbin/caps-sudo disarm"
echo ">> optional: float the prompt window in hyprland.conf:"
echo "     windowrulev2 = float, class:^(caps-sudo-auth)$"
