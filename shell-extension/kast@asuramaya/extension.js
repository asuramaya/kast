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

function dim(text) {
    return new PopupMenu.PopupMenuItem(text, {reactive: false, can_focus: false});
}

// A single "Kast" tile holding both casting (outbound) and the AirPlay receiver
// (inbound). The pill opens the cast picker; the ⌄ menu has everything.
const KastToggle = GObject.registerClass(
class KastToggle extends QuickMenuToggle {
    _init(onPrefs) {
        super._init({
            title: 'Kast',
            subtitle: 'Cast or receive',
            iconName: 'video-display-symbolic',
            toggleMode: false,
        });
        this._onPrefs = onPrefs;
        this.menu.setHeader('video-display-symbolic', 'Kast', 'Cast & AirPlay');

        // --- Cast (static actions) ---
        const castActions = new PopupMenu.PopupMenuSection();
        castActions.addMenuItem(dim('Cast'));
        castActions.addAction('Display Cast…', () => runKast(['open-display-cast']));
        castActions.addAction('Miracast (drops Wi-Fi)…', () => runKast(['open-display-cast', '--drop-wifi']));
        this.menu.addMenuItem(castActions);

        // --- Cast targets (dynamic) ---
        this._castSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._castSection);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        // --- Receiver (dynamic) ---
        this._receiverSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._receiverSection);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        // --- Settings links (static) ---
        const settings = new PopupMenu.PopupMenuSection();
        settings.addAction('Sound Settings…', () => runKast(['open-sound']));
        settings.addAction('Display Settings…', () => runKast(['open-display']));
        settings.addAction('Kast Settings…', () => this._onPrefs?.());
        this.menu.addMenuItem(settings);

        // --- Footer: update + version (dynamic) ---
        this._footerSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._footerSection);

        // Clicking the pill body opens the cast picker.
        this.connect('clicked', () => runKast(['open-display-cast']));
    }

    render(data) {
        const status = data.status ?? {};
        const active = !!status.receiver?.active;
        const mode = status.mirror_mode ?? 'mirror';
        this.subtitle = active ? `Receiving · ${mode}` : 'Cast or receive';

        this._renderCast(data);
        this._renderReceiver(status, active, mode);
        this._renderFooter(status, data.updateInfo);
    }

    _renderCast({castTargets = [], miracastTargets = [], miracastScanning = false}) {
        const s = this._castSection;
        s.removeAll();
        s.addMenuItem(dim(`Chromecast (${castTargets.length})`));
        if (castTargets.length === 0)
            s.addMenuItem(dim('No targets found'));
        else
            for (const t of castTargets)
                s.addAction(t.name || t.address || 'Unknown device', () => runKast(['open-display-cast']));
        s.addAction('Rescan Chromecast', () => this.onRescanCast?.());

        s.addMenuItem(dim(`Miracast (${miracastTargets.length})`));
        for (const t of miracastTargets)
            s.addAction(t.name || t.hwaddr || 'Unknown display', () => runKast(['open-display-cast', '--drop-wifi']));
        if (miracastScanning)
            s.addMenuItem(dim('Scanning for Miracast displays…'));
        else
            s.addAction('Scan for Miracast displays', () => this.onScanMiracast?.());
    }

    _renderReceiver(status, active, mode) {
        const s = this._receiverSection;
        s.removeAll();

        const toggle = new PopupMenu.PopupSwitchMenuItem('AirPlay Receiver', active);
        toggle.connect('toggled', (_item, state) => runKast([state ? 'receiver-start' : 'receiver-stop']));
        s.addMenuItem(toggle);

        s.addMenuItem(dim('Mode'));
        for (const [label, value] of [['Mirror', 'mirror'], ['Video Overlay', 'video-overlay']])
            s.addAction(`${mode === value ? '●  ' : '    '}${label}`, () => runKast(['set-mode', value]));

        s.addMenuItem(dim('AirPlay Output'));
        const sinks = (status.outbound?.sinks ?? []).filter(sink => sink.raop);
        if (sinks.length === 0)
            s.addMenuItem(dim('No AirPlay outputs'));
        else
            for (const sink of sinks)
                s.addAction(`${sink.default ? '●  ' : '    '}${sink.name}`, () => runKast(['select-sink', `${sink.id}`]));
        s.addAction('Use Local Speakers', () => runKast(['select-local']));

        s.addAction('Restart Receiver', () => runKast(['receiver-restart']));
    }

    _renderFooter(status, updateInfo) {
        const s = this._footerSection;
        s.removeAll();
        if (updateInfo && updateInfo.update_available)
            s.addAction(`⬆ Update to v${updateInfo.latest}`, () => runKast(['update']));
        s.addMenuItem(dim(`kast v${status.version ?? '?'}`));
    }
});

const KastIndicator = GObject.registerClass(
class KastIndicator extends SystemIndicator {
    _init(onPrefs) {
        super._init();

        this._data = {status: null, castTargets: [], miracastTargets: [], miracastScanning: false, updateInfo: null};

        this._toggle = new KastToggle(onPrefs);
        this._toggle.onRescanCast = () => this._discoverCastTargets();
        this._toggle.onScanMiracast = () => this._scanMiracast();
        this.quickSettingsItems.push(this._toggle);

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

    _render() {
        this._toggle.render(this._data);
    }

    _refresh() {
        readKastJson(['status', '--json'], status => {
            this._data.status = status;
            this._render();
        });
    }

    _discoverCastTargets() {
        readKastJson(['cast-targets', '--json'], targets => {
            if (Array.isArray(targets)) {
                this._data.castTargets = targets;
                this._render();
            }
        });
        return GLib.SOURCE_CONTINUE;
    }

    _scanMiracast() {
        if (this._data.miracastScanning)
            return;
        this._data.miracastScanning = true;
        this._render();
        readKastJson(['miracast-targets', '--json'], targets => {
            this._data.miracastScanning = false;
            if (Array.isArray(targets))
                this._data.miracastTargets = targets;
            this._render();
        });
    }

    _checkUpdate() {
        readKastJson(['check-update', '--json'], info => {
            if (info && typeof info === 'object') {
                this._data.updateInfo = info;
                this._render();
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
        this._indicator = new KastIndicator(() => this.openPreferences());
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
