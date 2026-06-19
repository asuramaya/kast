import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const CLI_PATH = `${GLib.get_home_dir()}/.local/bin/kast`;

function runKast(args) {
    // Fire the command but still watch its exit: from the tile there is no
    // terminal, so a failed cast/connect would otherwise vanish silently. On a
    // non-zero exit we surface kast's own last stderr line as a notification.
    // User-cancel paths (e.g. closing the zenity picker) exit 0, so they stay
    // quiet.
    try {
        const proc = Gio.Subprocess.new(
            [CLI_PATH, ...args],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            try {
                const [, , stderr] = p.communicate_utf8_finish(res);
                if (!p.get_successful()) {
                    const msg = (stderr || '').trim().split('\n').filter(Boolean).pop();
                    Main.notify('Kast', msg || `kast ${args[0] ?? ''} failed`.trim());
                }
            } catch (error) {
                logError(error, 'kast: command failed');
            }
        });
    } catch (error) {
        logError(error, 'kast: command failed');
        Main.notify('Kast', `Failed to run kast ${args[0] ?? ''}`.trim());
    }
}

// Always invokes onDone exactly once — with the parsed JSON, or null on any
// failure — so callers can clear in-flight flags without leaking them on error.
function readKastJson(args, onDone) {
    try {
        const proc = Gio.Subprocess.new(
            [CLI_PATH, ...args],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            let parsed = null;
            try {
                const [, stdout] = p.communicate_utf8_finish(res);
                parsed = JSON.parse(stdout);
            } catch (error) {
                logError(error, 'kast: JSON parse failed');
            }
            onDone(parsed);
        });
    } catch (error) {
        logError(error, 'kast: subprocess failed');
        onDone(null);
    }
}

function dim(text) {
    return new PopupMenu.PopupMenuItem(text, {reactive: false, can_focus: false});
}

// One "Kast" tile. The menu is intentionally lean: a contextual casting status,
// two collapsible groups (Cast to… / Receive) for the dynamic lists, and links
// to the Control Center window and the preferences dialog. All configuration
// (receiver names, mode, PIN, Wi-Fi behaviour) lives in preferences, not here.
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

        // Contextual: shown only while a display stream is live.
        this._statusSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._statusSection);

        // Cast to… — collapsible list of discovered targets. Expanding it is the
        // moment the user is about to pick a target, so refresh with fresh mDNS
        // queries right then (silently — the explicit Rescan button is what shows
        // the "Scanning…" label).
        this._castMenu = new PopupMenu.PopupSubMenuMenuItem('Cast to…', true);
        this._castMenu.icon.icon_name = 'video-display-symbolic';
        this._castMenu.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this.onCastMenuOpen?.();
        });
        this.menu.addMenuItem(this._castMenu);

        // Receive — collapsible on/off switches for the inbound receivers.
        this._receiverMenu = new PopupMenu.PopupSubMenuMenuItem('Receive', true);
        this._receiverMenu.icon.icon_name = 'audio-input-microphone-symbolic';
        this.menu.addMenuItem(this._receiverMenu);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        // Static links: the full remote and all configuration live elsewhere.
        this.menu.addAction('Control Center…', () => runKast(['control-center']));
        this.menu.addAction('Kast Settings…', () => this._onPrefs?.());

        // Footer: version + optional update.
        this._footerSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._footerSection);

        // Clicking the pill opens the graphical picker.
        this.connect('clicked', () => runKast(['pick']));
    }

    render(data) {
        const status = data.status ?? {};
        const cast = status.outbound?.cast ?? {};
        const anyRecv = status.receiver?.active || status.audio_receiver?.active ||
            status.youtube_receiver?.active;
        this.subtitle = cast.active
            ? `Casting · ${cast.target ?? 'display'}`
            : anyRecv ? 'Receiving' : 'Cast or receive';
        this.checked = !!(cast.active || anyRecv);

        this._renderStatus(cast);
        this._renderCast(data);
        this._renderReceivers(status);
        this._renderFooter(status, data.updateInfo);
    }

    _renderStatus(cast) {
        const s = this._statusSection;
        s.removeAll();
        if (cast.active) {
            s.addMenuItem(dim(`Casting · ${cast.target ?? 'display'}`));
            s.addAction('Disconnect', () => runKast(['disconnect']));
            s.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        }
    }

    _renderCast(data) {
        const {castTargets = [], airplayTargets = [], miracastTargets = [], miracastScanning = false, castScanning = false} = data;
        const canFile = !!data.status?.outbound?.chromecast_filecast;
        const m = this._castMenu.menu;
        m.removeAll();

        const total = castTargets.length + airplayTargets.length + miracastTargets.length;
        this._castMenu.label.text = total ? `Cast to… (${total})` : 'Cast to…';

        if (castTargets.length) {
            m.addMenuItem(dim('Chromecast'));
            for (const t of castTargets) {
                const name = t.name || t.address || 'Device';
                m.addAction(`${name} — mirror screen`, () => runKast(['display-connect', name]));
                if (canFile)
                    m.addAction(`${name} — cast file…`, () => runKast(['cast-file-pick', name]));
            }
        }
        if (airplayTargets.length) {
            m.addMenuItem(dim('AirPlay'));
            for (const t of airplayTargets) {
                const ref = t.address || t.name;
                m.addAction(`${t.name || ref || 'Receiver'} — cast file…`, () => runKast(['airplay-pick', ref]));
            }
        }
        if (miracastTargets.length) {
            m.addMenuItem(dim('Miracast'));
            for (const t of miracastTargets)
                m.addAction(t.name || t.hwaddr || 'Display', () => runKast(['display-connect', t.name || t.hwaddr || '']));
        }
        if (!total)
            m.addMenuItem(dim('No devices found'));

        m.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        m.addAction('Open picker…', () => runKast(['pick']));
        m.addAction(miracastScanning ? 'Scanning for Miracast…' : 'Scan for Miracast', () => this.onScanMiracast?.());
        m.addAction(castScanning ? 'Scanning…' : 'Rescan', () => this.onRescanCast?.());
    }

    _renderReceivers(status) {
        const m = this._receiverMenu.menu;
        m.removeAll();
        const addSwitch = (label, active, startCmd, stopCmd) => {
            const item = new PopupMenu.PopupSwitchMenuItem(label, !!active);
            item.connect('toggled', (_i, state) => runKast([state ? startCmd : stopCmd]));
            m.addMenuItem(item);
        };
        addSwitch('AirPlay — screen', status.receiver?.active, 'receiver-start', 'receiver-stop');
        if (status.audio_receiver?.installed)
            addSwitch('AirPlay — audio', status.audio_receiver?.active, 'audio-receiver-start', 'audio-receiver-stop');
        if (status.youtube_receiver?.installed)
            addSwitch('YouTube', status.youtube_receiver?.active, 'youtube-receiver-start', 'youtube-receiver-stop');
        else if (status.youtube_receiver?.reason)
            // Surface YouTube even when it can't run yet, with what it needs —
            // otherwise the feature just silently vanishes from the menu.
            m.addMenuItem(dim(`YouTube — ${status.youtube_receiver.reason}`));

        const anyOn = status.receiver?.active || status.audio_receiver?.active || status.youtube_receiver?.active;
        this._receiverMenu.label.text = anyOn ? 'Receive · on' : 'Receive';
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

        this._data = {status: null, castTargets: [], miracastTargets: [], miracastScanning: false, airplayTargets: [], castScanning: false, updateInfo: null};
        this._castScanning = false;
        this._airplayScanning = false;

        this._toggle = new KastToggle(onPrefs);
        this._toggle.onRescanCast = () => this._rescanCast();
        this._toggle.onScanMiracast = () => this._scanMiracast();
        this._toggle.onCastMenuOpen = () => this._discoverAll(true);
        this.quickSettingsItems.push(this._toggle);

        this._refresh();
        this._statusTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
        // Background discovery: a cheap cached read every 20s keeps renders
        // responsive; every 3rd tick (~60s) issues fresh mDNS queries to keep
        // avahi's cache warm, so the list stays accurate even before the user
        // opens the menu. Opening the cast menu also triggers an active refresh.
        this._discoverTick = 0;
        this._discoverAll();
        this._discoverTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 20, () => {
            this._discoverTick += 1;
            this._discoverAll(this._discoverTick % 3 === 0);
            return GLib.SOURCE_CONTINUE;
        });
        this._checkUpdate();
        this._updateTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 6 * 3600, () => this._checkUpdate());
    }

    _discoverAll(active = false) {
        this._discoverCastTargets(active);
        this._discoverAirplayTargets(active);
    }

    _render() {
        this._toggle.render(this._data);
    }

    _refresh() {
        readKastJson(['status', '--json'], status => {
            // Guard the shape: a non-object (null / error) would throw in render.
            if (status && typeof status === 'object' && !Array.isArray(status)) {
                this._data.status = status;
                this._render();
            }
        });
    }

    _rescanCast() {
        // Explicit Rescan: issue fresh mDNS queries (--scan) for both protocols
        // and show a "Scanning…" affordance until both return, so the user gets
        // feedback that something more than a cache re-read is happening.
        if (this._data.castScanning)
            return;
        this._data.castScanning = true;
        this._render();
        let pending = 2;
        const done = () => {
            if (--pending === 0) {
                this._data.castScanning = false;
                this._render();
            }
        };
        this._discoverCastTargets(true, done);
        this._discoverAirplayTargets(true, done);
    }

    _discoverCastTargets(active = false, onDone) {
        // In-flight guard: this runs on the discovery timer and on demand (Rescan
        // / menu open); without it, overlapping `kast` subprocesses spawn and a
        // slow older call can overwrite newer results. `active` issues fresh mDNS
        // queries (slower) instead of reading avahi's cache.
        if (this._castScanning) {
            onDone?.();
            return;
        }
        this._castScanning = true;
        const args = active ? ['cast-targets', '--json', '--scan'] : ['cast-targets', '--json'];
        readKastJson(args, targets => {
            this._castScanning = false;
            if (Array.isArray(targets)) {
                this._data.castTargets = targets;
                this._render();
            }
            onDone?.();
        });
    }

    _discoverAirplayTargets(active = false, onDone) {
        if (this._airplayScanning) {
            onDone?.();
            return;
        }
        this._airplayScanning = true;
        const args = active ? ['airplay-targets', '--json', '--scan'] : ['airplay-targets', '--json'];
        readKastJson(args, targets => {
            this._airplayScanning = false;
            if (Array.isArray(targets)) {
                this._data.airplayTargets = targets;
                this._render();
            }
            onDone?.();
        });
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
        for (const id of [this._statusTimer, this._discoverTimer, this._updateTimer]) {
            if (id)
                GLib.source_remove(id);
        }
        this._statusTimer = this._discoverTimer = this._updateTimer = 0;
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
