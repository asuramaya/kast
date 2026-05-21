import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const CLI_PATH = `${GLib.get_home_dir()}/.local/bin/kast`;

const KastIndicator = GObject.registerClass(
class KastIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Kast');

        this._icon = new St.Icon({
            icon_name: 'video-display-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(this._icon);

        this._dynamicItems = [];
        this._castTargets = [];
        this._miracastTargets = [];
        this._miracastScanning = false;
        this._updateInfo = null;
        this._statusItem = new PopupMenu.PopupMenuItem('Loading cast status…', {
            reactive: false,
            can_focus: false,
        });
        this.menu.addMenuItem(this._statusItem);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this.menu.addAction('Display Cast…', () => this._spawn([CLI_PATH, 'open-display-cast']));
        this.menu.addAction('Display Cast — Miracast (drops Wi-Fi)…', () => this._spawn([CLI_PATH, 'open-display-cast', '--drop-wifi']));
        this.menu.addAction('Sound Settings…', () => this._spawn([CLI_PATH, 'open-sound']));
        this.menu.addAction('Start Receiver', () => this._spawn([CLI_PATH, 'receiver-start']));
        this.menu.addAction('Stop Receiver', () => this._spawn([CLI_PATH, 'receiver-stop']));
        this.menu.addAction('Use Local Speakers', () => this._spawn([CLI_PATH, 'select-local']));
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._airplayHeading = new PopupMenu.PopupMenuItem('AirPlay Outputs', {
            reactive: false,
            can_focus: false,
        });
        this.menu.addMenuItem(this._airplayHeading);
        this._refreshItem = new PopupMenu.PopupMenuItem('Refresh');
        this._refreshItem.connect('activate', () => this._refresh());
        this.menu.addMenuItem(this._refreshItem);

        this._refresh();
        this._timerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
        // mDNS discovery runs on its own slower cadence and never blocks status.
        this._discoverCastTargets();
        this._castTimerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 20, () => this._discoverCastTargets());
        // Update checks hit the network; keep them infrequent.
        this._checkUpdate();
        this._updateTimerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 6 * 3600, () => this._checkUpdate());
    }

    destroy() {
        if (this._timerId) {
            GLib.source_remove(this._timerId);
            this._timerId = 0;
        }
        if (this._castTimerId) {
            GLib.source_remove(this._castTimerId);
            this._castTimerId = 0;
        }
        if (this._updateTimerId) {
            GLib.source_remove(this._updateTimerId);
            this._updateTimerId = 0;
        }
        super.destroy();
    }

    _spawn(argv) {
        try {
            Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
        } catch (error) {
            logError(error, 'Kast command failed');
        }
    }

    _readJson(argv, onDone) {
        try {
            const proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            proc.communicate_utf8_async(null, null, (subprocess, result) => {
                try {
                    const [, stdout] = subprocess.communicate_utf8_finish(result);
                    onDone(JSON.parse(stdout));
                } catch (error) {
                    logError(error, 'Kast JSON parse failed');
                }
            });
        } catch (error) {
            logError(error, 'Kast subprocess failed');
        }
    }

    _clearDynamicItems() {
        for (const item of this._dynamicItems) {
            item.destroy();
        }
        this._dynamicItems = [];
    }

    _addDynamic(item) {
        this.menu.addMenuItem(item, this.menu._getMenuItems().indexOf(this._refreshItem));
        this._dynamicItems.push(item);
    }

    _discoverCastTargets() {
        this._readJson([CLI_PATH, 'cast-targets', '--json'], targets => {
            if (Array.isArray(targets)) {
                this._castTargets = targets;
                this._refresh();
            }
        });
        return GLib.SOURCE_CONTINUE;
    }

    _renderCastTargets() {
        const heading = new PopupMenu.PopupMenuItem(`Chromecast Targets (${this._castTargets.length})`, {
            reactive: false,
            can_focus: false,
        });
        this._addDynamic(heading);

        if (this._castTargets.length === 0) {
            this._addDynamic(new PopupMenu.PopupMenuItem('No cast targets found', {
                reactive: false,
                can_focus: false,
            }));
        } else {
            for (const target of this._castTargets) {
                const name = target.name || target.address || 'Unknown device';
                const item = new PopupMenu.PopupMenuItem(name);
                // gnome-network-displays owns the screencast pipeline and exposes
                // no connect API, so selecting a target opens its picker.
                item.connect('activate', () => this._spawn([CLI_PATH, 'open-display-cast']));
                this._addDynamic(item);
            }
        }
        const rescan = new PopupMenu.PopupMenuItem('Rescan Chromecast Targets');
        rescan.connect('activate', () => this._discoverCastTargets());
        this._addDynamic(rescan);
    }

    _scanMiracast() {
        // On-demand only: a P2P find shares the Wi-Fi radio, so it is never run
        // on a timer.
        if (this._miracastScanning)
            return;
        this._miracastScanning = true;
        this._refresh();
        this._readJson([CLI_PATH, 'miracast-targets', '--json'], targets => {
            this._miracastScanning = false;
            if (Array.isArray(targets))
                this._miracastTargets = targets;
            this._refresh();
        });
    }

    _renderMiracast() {
        const heading = new PopupMenu.PopupMenuItem(`Miracast Displays (${this._miracastTargets.length})`, {
            reactive: false,
            can_focus: false,
        });
        this._addDynamic(heading);

        for (const target of this._miracastTargets) {
            const name = target.name || target.hwaddr || 'Unknown display';
            const item = new PopupMenu.PopupMenuItem(name);
            // Miracast needs the radio; hand off to gnd and drop Wi-Fi.
            item.connect('activate', () => this._spawn([CLI_PATH, 'open-display-cast', '--drop-wifi']));
            this._addDynamic(item);
        }

        if (this._miracastScanning) {
            this._addDynamic(new PopupMenu.PopupMenuItem('Scanning for Miracast displays…', {
                reactive: false,
                can_focus: false,
            }));
        } else {
            const scan = new PopupMenu.PopupMenuItem('Scan for Miracast displays');
            scan.connect('activate', () => this._scanMiracast());
            this._addDynamic(scan);
        }
    }

    _checkUpdate() {
        this._readJson([CLI_PATH, 'check-update', '--json'], info => {
            if (info && typeof info === 'object') {
                this._updateInfo = info;
                this._refresh();
            }
        });
        return GLib.SOURCE_CONTINUE;
    }

    _renderUpdate() {
        if (!this._updateInfo || !this._updateInfo.update_available)
            return;
        const item = new PopupMenu.PopupMenuItem(`⬆ Update to v${this._updateInfo.latest}`);
        // The extension runs in gnome-shell, so the installer's kast-tray restart
        // won't interrupt this update.
        item.connect('activate', () => this._spawn([CLI_PATH, 'update']));
        this._addDynamic(item);
    }

    _renderMode(mode) {
        this._addDynamic(new PopupMenu.PopupMenuItem('Receiver Mode', {reactive: false, can_focus: false}));
        for (const [label, value] of [['Mirror', 'mirror'], ['Video Overlay', 'video-overlay']]) {
            const item = new PopupMenu.PopupMenuItem(mode === value ? `● ${label}` : `    ${label}`);
            item.connect('activate', () => this._spawn([CLI_PATH, 'set-mode', value]));
            this._addDynamic(item);
        }
    }

    _refresh() {
        this._readJson([CLI_PATH, 'status', '--json'], status => {
            const receiverState = status.receiver?.active ? 'receiver on' : 'receiver off';
            const sinkCount = status.outbound?.airplay_sink_count ?? 0;
            const mode = status.mirror_mode ?? 'mirror';
            this._statusItem.label.text = `${receiverState} · mode: ${mode} · ${sinkCount} AirPlay · kast v${status.version ?? '?'}`;

            this._clearDynamicItems();
            const sinks = status.outbound?.sinks?.filter(sink => sink.raop) ?? [];

            if (sinks.length === 0) {
                this._addDynamic(new PopupMenu.PopupMenuItem('No AirPlay sinks discovered', {
                    reactive: false,
                    can_focus: false,
                }));
            } else {
                for (const sink of sinks) {
                    const label = sink.default ? `• ${sink.name}` : sink.name;
                    const item = new PopupMenu.PopupMenuItem(label);
                    item.connect('activate', () => this._spawn([CLI_PATH, 'select-sink', `${sink.id}`]));
                    this._addDynamic(item);
                }
            }

            this._renderCastTargets();
            this._renderMiracast();
            this._renderMode(mode);
            this._renderUpdate();
        });
    }
});

export default class KastCastExtension extends Extension {
    enable() {
        this._indicator = new KastIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
