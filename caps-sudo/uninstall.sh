#!/usr/bin/env bash
# Remove caps-sudo cleanly. Run: sudo ./uninstall.sh   (keeps keyd installed)
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

# disarm first, whatever state we're in
[ -x /usr/local/sbin/caps-sudo ] && /usr/local/sbin/caps-sudo disarm || rm -f /etc/sudoers.d/90-caps-armed

systemctl disable --now caps-sudo-disarm-on-boot.service 2>/dev/null || true
rm -f /etc/systemd/system/caps-sudo-disarm-on-boot.service
systemctl daemon-reload

# unwire keyd: if our config is the whole file, drop it; else strip just our line
if [ -f /etc/keyd/default.conf ]; then
  if grep -q 'caps-sudo keypress' /etc/keyd/default.conf && \
     [ "$(grep -vcE '^\s*(#|$)' /etc/keyd/default.conf)" -le 3 ]; then
    rm -f /etc/keyd/default.conf
  else
    sed -i '/caps-sudo keypress/d' /etc/keyd/default.conf
  fi
  systemctl restart keyd 2>/dev/null || true
fi

rm -f /usr/share/polkit-1/actions/com.fursman.caps-sudo.policy

# on-screen indicator (installed into the invoking user's home)
OWNER="${SUDO_USER:-}"
if [ -n "$OWNER" ]; then
  OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
  rm -rf "$OWNER_HOME/.local/share/gnome-shell/extensions/caps-sudo-indicator@fursman.com"
fi

rm -f /usr/local/sbin/caps-sudo
echo ">> caps-sudo removed. (keyd left installed; 'sudo apt remove keyd' to drop it too.)"
echo ">> CapsLock returns to normal after: sudo keyd reload"
