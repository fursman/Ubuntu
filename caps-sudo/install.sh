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

# 3b. polkit action -- lets CapsLock raise the desktop's native auth dialog
#     instead of opening a terminal. auth_admin (never auth_admin_keep), so
#     every arm needs a fresh password.
echo ">> installing polkit action"
install -m 0644 "$DIR/com.fursman.caps-sudo.policy" /usr/share/polkit-1/actions/

# 3c. on-screen indicator.
#     The CapsLock LED is the primary "armed" light and still works wherever the
#     keyboard driver honours brightness writes (check with: caps-sudo led-test).
#     The on-screen indicator is ADDITIVE -- it is the signal that survives
#     laptops whose driver ignores the LED, and it is visible when you are not
#     looking at the keyboard.
GNOME_EXT_UUID=caps-sudo-indicator@fursman.com
GNOME_EXT_SRC="$DIR/indicator/gnome/$GNOME_EXT_UUID"
OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
if [ -d "$GNOME_EXT_SRC" ] && command -v gnome-shell >/dev/null 2>&1; then
  echo ">> installing GNOME Shell indicator for $OWNER"
  EXT_DIR="$OWNER_HOME/.local/share/gnome-shell/extensions/$GNOME_EXT_UUID"
  install -d -o "$OWNER" -g "$OWNER" "$EXT_DIR"
  install -m 0644 -o "$OWNER" -g "$OWNER" "$GNOME_EXT_SRC"/* "$EXT_DIR"/
  # Pre-enable it; GNOME cannot hot-load a new extension on Wayland, so it
  # comes up on the user's next login.
  sudo -u "$OWNER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$OWNER")" \
    gsettings get org.gnome.shell enabled-extensions 2>/dev/null \
    | grep -q "$GNOME_EXT_UUID" || \
    sudo -u "$OWNER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$OWNER")" bash -c \
      'cur=$(gsettings get org.gnome.shell enabled-extensions); \
       gsettings set org.gnome.shell enabled-extensions "${cur%]}, '"'"'"'$0'"'"'"']"' \
      "$GNOME_EXT_UUID" 2>/dev/null || true
  echo "   (log out and back in to see it -- Wayland cannot hot-load extensions)"
fi
if command -v waybar >/dev/null 2>&1; then
  echo ">> waybar detected: add the module from $DIR/indicator/waybar/ to your config"
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
echo ">> check whether YOUR keyboard's CapsLock LED works:  sudo caps-sudo led-test"
echo ">> verify the LED responds:  sudo /usr/local/sbin/caps-sudo arm-commit; sleep 2; sudo /usr/local/sbin/caps-sudo disarm"
echo ">> optional: float the prompt window in hyprland.conf:"
echo "     windowrulev2 = float, class:^(caps-sudo-auth)$"
