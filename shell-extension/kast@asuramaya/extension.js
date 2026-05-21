import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const CLI_PATH = `${GLib.get_home_dir()}/.local/bin/kast`;

function runKast(args) {
    try {
        Gio.Subprocess.new([CLI_PATH, ...args], Gio.SubprocessFlags.NONE);
    } catch (error) {
        logError(error, 'kast: command failed');
    }
}

function readKastJson(args, onDone) {
    try {
        const proc = Gio.Subprocess.new(
            [CLI_PATH, ...args],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            try {
                const [, stdout] = p.communicate_utf8_finish(res);
                onDone(JSON.parse(stdout));
            } catch (error) {
                logError(error, 'kast: JSON parse failed');
            }
        });
    } catch (error) {
        logError(error, 'kast: subprocess failed');
    }
}

function dimItem(text) {
    return new PopupMenu.PopupMenuItem(text, {reactive: false, can_focus: false});
}

// "Cast" tile — outbound display casting (Chromecast + Miracast).
const CastToggle = GObject.registerClass(
class CastToggle extends QuickMenuToggle {
    _init() {
        super._init({
            title: 'Cast',
            subtitle: 'to a display',
            iconName: 'video-display-symbolic',
            toggleMode: false,
        });
        this.menu.setHeader('video-display-symbolic', 'Cast', 'Wireless display');

        // Callbacks wired up by the indicator.
        this.onRescanCast = null;
        this.onScanMiracast = null;

        const actions = new PopupMenu.PopupMenuSection();
        actions.addAction('Display Cast…', () => runKast(['open-display-cast']));
        actions.addAction('Miracast (drops Wi-Fi)…', () => runKast(['open-display-cast', '--drop-wifi']));
        this.menu.addMenuItem(actions);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        // Rebuilt on each discovery.
        this._targets = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._targets);

        // Clicking the pill body opens the cast picker.
        this.connect('clicked', () => runKast(['open-display-cast']));
    }

    updateTargets(castTargets, miracastTargets, scanning) {
        const total = castTargets.length + miracastTargets.length;
        this.subtitle = total > 0 ? `${total} device${total === 1 ? '' : 's'} found` : 'to a display';

        const s = this._targets;
        s.removeAll();

        s.addMenuItem(dimItem(`Chromecast (${castTargets.length})`));
        if (castTargets.length === 0) {
            s.addMenuItem(dimItem('No targets found'));
        } else {
            for (const t of castTargets)
                s.addAction(t.name || t.address || 'Unknown device', () => runKast(['open-display-cast']));
        }
        s.addAction('Rescan Chromecast', () => this.onRescanCast?.());

        s.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        s.addMenuItem(dimItem(`Miracast (${miracastTargets.length})`));
        for (const t of miracastTargets)
            s.addAction(t.name || t.hwaddr || 'Unknown display', () => runKast(['open-display-cast', '--drop-wifi']));
        if (scanning)
            s.addMenuItem(dimItem('Scanning for Miracast displays…'));
        else
            s.addAction('Scan for Miracast displays', () => this.onScanMiracast?.());
    }
});

// "Receiver" tile — inbound AirPlay receiver; the pill toggles it on/off.
const ReceiverToggle = GObject.registerClass(
class ReceiverToggle extends QuickMenuToggle {
    _init() {
        super._init({
            title: 'Receiver',
            subtitle: 'AirPlay',
            iconName: 'computer-symbolic',
            toggleMode: true,
        });
        this.menu.setHeader('computer-symbolic', 'AirPlay Receiver', 'Receive screen + audio');

        this._dynamic = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._dynamic);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const fixed = new PopupMenu.PopupMenuSection();
        fixed.addAction('Restart Receiver', () => runKast(['receiver-restart']));
        fixed.addAction('Sound Settings…', () => runKast(['open-sound']));
        this.menu.addMenuItem(fixed);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._footer = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._footer);

        // Pill click toggles the receiver.
        this.connect('clicked', () => runKast(['toggle-receiver']));
    }

    update(status, updateInfo) {
        const active = !!status.receiver?.active;
        const mode = status.mirror_mode ?? 'mirror';
        this.checked = active;
        this.subtitle = active ? `On · ${mode}` : 'Off';

        const s = this._dynamic;
        s.removeAll();
        s.addMenuItem(dimItem('Mode'));
        for (const [label, value] of [['Mirror', 'mirror'], ['Video Overlay', 'video-overlay']])
            s.addAction(`${mode === value ? '●  ' : '    '}${label}`, () => runKast(['set-mode', value]));

        s.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        s.addMenuItem(dimItem('AirPlay Output'));
        const sinks = (status.outbound?.sinks ?? []).filter(sink => sink.raop);
        if (sinks.length === 0)
            s.addMenuItem(dimItem('No AirPlay outputs'));
        else
            for (const sink of sinks)
                s.addAction(`${sink.default ? '●  ' : '    '}${sink.name}`, () => runKast(['select-sink', `${sink.id}`]));
        s.addAction('Use Local Speakers', () => runKast(['select-local']));

        const f = this._footer;
        f.removeAll();
        if (updateInfo && updateInfo.update_available)
            f.addAction(`⬆ Update to v${updateInfo.latest}`, () => runKast(['update']));
        f.addMenuItem(dimItem(`kast v${status.version ?? '?'}`));
    }
});

const KastIndicator = GObject.registerClass(
class KastIndicator extends SystemIndicator {
    _init() {
        super._init();

        this._status = null;
        this._castTargets = [];
        this._miracastTargets = [];
        this._miracastScanning = false;
        this._updateInfo = null;

        this._cast = new CastToggle();
        this._receiver = new ReceiverToggle();
        this._cast.onRescanCast = () => this._discoverCastTargets();
        this._cast.onScanMiracast = () => this._scanMiracast();
        this.quickSettingsItems.push(this._cast);
        this.quickSettingsItems.push(this._receiver);

        this._refresh();
        this._statusTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
        this._discoverCastTargets();
        this._castTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 20, () => this._discoverCastTargets());
        this._checkUpdate();
        this._updateTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 6 * 3600, () => this._checkUpdate());
    }

    _refresh() {
        readKastJson(['status', '--json'], status => {
            this._status = status;
            this._receiver.update(status, this._updateInfo);
            this._cast.updateTargets(this._castTargets, this._miracastTargets, this._miracastScanning);
        });
    }

    _discoverCastTargets() {
        readKastJson(['cast-targets', '--json'], targets => {
            if (Array.isArray(targets)) {
                this._castTargets = targets;
                this._cast.updateTargets(this._castTargets, this._miracastTargets, this._miracastScanning);
            }
        });
        return GLib.SOURCE_CONTINUE;
    }

    _scanMiracast() {
        if (this._miracastScanning)
            return;
        this._miracastScanning = true;
        this._cast.updateTargets(this._castTargets, this._miracastTargets, true);
        readKastJson(['miracast-targets', '--json'], targets => {
            this._miracastScanning = false;
            if (Array.isArray(targets))
                this._miracastTargets = targets;
            this._cast.updateTargets(this._castTargets, this._miracastTargets, false);
        });
    }

    _checkUpdate() {
        readKastJson(['check-update', '--json'], info => {
            if (info && typeof info === 'object') {
                this._updateInfo = info;
                if (this._status)
                    this._receiver.update(this._status, info);
            }
        });
        return GLib.SOURCE_CONTINUE;
    }

    destroy() {
        for (const id of [this._statusTimer, this._castTimer, this._updateTimer]) {
            if (id)
                GLib.source_remove(id);
        }
        this._statusTimer = this._castTimer = this._updateTimer = 0;
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class KastExtension extends Extension {
    enable() {
        this._indicator = new KastIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
