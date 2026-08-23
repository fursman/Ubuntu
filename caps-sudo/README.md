# caps-sudo

CapsLock arms/disarms passwordless `sudo`; the CapsLock LED is the "armed" light.

**Sharp edge:** while armed, any `sudo` succeeds with no password. `setup.sh` never
installs this. Read [../docs/CAPS-SUDO.md](../docs/CAPS-SUDO.md) first.

```
sudo caps-sudo/install.sh      # needs keyd; not while a release upgrade is running
sudo caps-sudo/uninstall.sh    # clean removal
```

Files: `caps-sudo` (root helper, run by keyd), `keyd-default.conf` (CapsLock ->
helper), `caps-sudo-disarm-on-boot.service` (force-disarm at boot).
