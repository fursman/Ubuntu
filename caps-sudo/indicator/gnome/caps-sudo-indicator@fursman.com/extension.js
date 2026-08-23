// caps-sudo Indicator — red top-bar pill while passwordless sudo is ARMED.
//
// State is the presence of /etc/sudoers.d/90-caps-armed, exactly as caps-sudo
// defines it. /etc/sudoers.d is world-listable (drwxr-xr-x), so an unprivileged
// shell process can test existence without ever reading the file's contents.

import GObject from 'gi://GObject';
import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ARMED_FILE = '/etc/sudoers.d/90-caps-armed';
const WATCH_DIR = '/etc/sudoers.d';
const HELPER = '/usr/local/sbin/caps-sudo';

const CapsSudoIndicator = GObject.registerClass(
class CapsSudoIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'caps-sudo', false);

        const pill = new St.BoxLayout({
            style_class: 'caps-sudo-pill',
            y_align: Clutter.ActorAlign.CENTER,
        });
        pill.add_child(new St.Icon({
            icon_name: 'dialog-warning-symbolic',
            style_class: 'caps-sudo-icon',
            y_align: Clutter.ActorAlign.CENTER,
        }));
        pill.add_child(new St.Label({
            text: 'sudo armed',
            style_class: 'caps-sudo-label',
            y_align: Clutter.ActorAlign.CENTER,
        }));
        this.add_child(pill);

        // While armed, sudo is passwordless — so `sudo -n` disarms with no prompt.
        const item = new PopupMenu.PopupMenuItem('Disarm passwordless sudo');
        item.connect('activate', () => this._disarm());
        this.menu.addMenuItem(item);
    }

    _disarm() {
        try {
            Gio.Subprocess.new(
                ['sudo', '-n', HELPER, 'disarm'],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE
            );
        } catch (e) {
            logError(e, 'caps-sudo-indicator: disarm failed');
        }
    }
});

export default class CapsSudoIndicatorExtension extends Extension {
    enable() {
        this._indicator = new CapsSudoIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');

        // Primary signal: inotify on the directory.
        try {
            this._monitor = Gio.File.new_for_path(WATCH_DIR)
                .monitor_directory(Gio.FileMonitorFlags.NONE, null);
            this._monitorId = this._monitor.connect('changed', () => this._sync());
        } catch (e) {
            logError(e, 'caps-sudo-indicator: file monitor failed, polling only');
        }

        // Safety reconcile, in case an inotify event is ever missed.
        this._timerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
            this._sync();
            return GLib.SOURCE_CONTINUE;
        });

        this._sync();
    }

    _sync() {
        if (!this._indicator)
            return;
        const armed = GLib.file_test(ARMED_FILE, GLib.FileTest.EXISTS);
        this._indicator.visible = armed;
        if (this._indicator.container)
            this._indicator.container.visible = armed;
    }

    disable() {
        if (this._timerId) {
            GLib.Source.remove(this._timerId);
            this._timerId = null;
        }
        if (this._monitor) {
            if (this._monitorId)
                this._monitor.disconnect(this._monitorId);
            this._monitor.cancel();
            this._monitor = null;
            this._monitorId = null;
        }
        this._indicator?.destroy();
        this._indicator = null;
    }
}
