import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const CONF_DIR = GLib.build_filenamev([GLib.get_user_config_dir(), 'kast']);
const CONF_PATH = GLib.build_filenamev([CONF_DIR, 'uxplay.conf']);
const CLI_PATH = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'kast']);

// kast's runtime config is a bash-sourced file (the CLI reads it), so prefs.js
// reads and rewrites that same file rather than introducing a GSettings schema.
function readConf() {
    let text = '';
    try {
        const [ok, bytes] = GLib.file_get_contents(CONF_PATH);
        if (ok)
            text = new TextDecoder().decode(bytes);
    } catch (_e) {
        // No config yet — fall back to defaults below.
    }
    const name = (text.match(/UXPLAY_NAME="([^"]*)"/) || [, 'Kast Receiver'])[1];
    const audioName = (text.match(/SHAIRPORT_NAME="([^"]*)"/) || [, 'Kast Audio'])[1];
    const ytName = (text.match(/YT_RECEIVER_NAME="([^"]*)"/) || [, 'Kast YouTube'])[1];
    const argsRaw = (text.match(/UXPLAY_ARGS=\(([^)]*)\)/) || [, ''])[1];
    const tokens = argsRaw.trim().split(/\s+/).filter(t => t.length > 0);
    return {
        name,
        audioName,
        ytName,
        tokens,
        h265: tokens.includes('-h265'),
        pin: tokens.includes('-pin'),
        dropWifi: /KAST_DROP_WIFI_DEFAULT=1/.test(text),
    };
}

// Rebuild UXPLAY_ARGS, preserving any custom flags the user added by hand while
// toggling the ones we manage (-h265, -pin and its optional numeric value).
function buildArgs(tokens, {h265, pin}) {
    const out = [];
    for (let i = 0; i < tokens.length; i++) {
        const t = tokens[i];
        if (t === '-h265')
            continue;
        if (t === '-pin') {
            if (/^\d+$/.test(tokens[i + 1] || ''))
                i++;
            continue;
        }
        out.push(t);
    }
    if (h265)
        out.push('-h265');
    if (pin)
        out.push('-pin');
    return out;
}

// The config is sourced by the bash CLI, so values must not be able to break
// out of their double-quoted assignment and execute. Strip the characters that
// trigger expansion or quoting tricks ($ ` " \ and newlines).
function sanitizeName(value) {
    return String(value).replace(/["`$\\\r\n]/g, '').trim();
}

// uxplay flags are simple tokens; refuse anything with whitespace or shell
// metacharacters so a preserved custom token can't inject into UXPLAY_ARGS=(…).
function safeToken(token) {
    return /^[A-Za-z0-9_=.:@x/+-]+$/.test(token);
}

function writeConf(state) {
    const args = buildArgs(state.tokens, state).filter(safeToken);
    const text = [
        '# shellcheck shell=bash',
        '# Managed by Kast preferences. Custom UXPLAY_ARGS flags are preserved.',
        '',
        `UXPLAY_NAME="${sanitizeName(state.name)}"`,
        `UXPLAY_ARGS=(${args.join(' ')})`,
        `SHAIRPORT_NAME="${sanitizeName(state.audioName)}"`,
        `YT_RECEIVER_NAME="${sanitizeName(state.ytName)}"`,
        `KAST_DROP_WIFI_DEFAULT=${state.dropWifi ? 1 : 0}`,
        '',
    ].join('\n');
    try {
        GLib.mkdir_with_parents(CONF_DIR, 0o755);
        GLib.file_set_contents(CONF_PATH, new TextEncoder().encode(text));
    } catch (e) {
        logError(e, 'kast prefs: failed to write config');
    }
}

// Mirror mode lives in kast's state (not the conf), so read/write it via the CLI.
function getMode() {
    try {
        const [ok, out] = GLib.spawn_sync(null, [CLI_PATH, 'get-mode'], null,
            GLib.SpawnFlags.DEFAULT, null);
        if (ok)
            return new TextDecoder().decode(out).trim() || 'mirror';
    } catch (_e) {
        // CLI missing — default below.
    }
    return 'mirror';
}

function runCli(args) {
    try {
        Gio.Subprocess.new([CLI_PATH, ...args], Gio.SubprocessFlags.NONE);
    } catch (e) {
        logError(e, 'kast prefs: CLI call failed');
    }
}

export default class KastPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const state = readConf();
        const save = () => writeConf(state);

        const page = new Adw.PreferencesPage({
            title: 'Kast',
            icon_name: 'video-display-symbolic',
        });
        window.add(page);

        // --- AirPlay screen receiver (uxplay) ---
        const screen = new Adw.PreferencesGroup({
            title: 'AirPlay Receiver (screen)',
            description: 'Receive screen mirroring from Apple devices. Changes apply on restart.',
        });
        page.add(screen);

        const nameRow = new Adw.EntryRow({title: 'Receiver name'});
        nameRow.text = state.name;
        nameRow.connect('changed', () => {
            state.name = nameRow.text;
            save();
        });
        screen.add(nameRow);

        const modeRow = new Adw.ComboRow({
            title: 'Mode',
            subtitle: 'How the received screen is shown',
            model: Gtk.StringList.new(['Mirror', 'Video overlay (fullscreen)']),
        });
        modeRow.selected = getMode() === 'video-overlay' ? 1 : 0;
        modeRow.connect('notify::selected', () => {
            runCli(['set-mode', modeRow.selected === 1 ? 'video-overlay' : 'mirror']);
        });
        screen.add(modeRow);

        const h265Row = new Adw.SwitchRow({
            title: 'H.265 video',
            subtitle: 'Use HEVC when the sending device supports it',
        });
        h265Row.active = state.h265;
        h265Row.connect('notify::active', () => {
            state.h265 = h265Row.active;
            save();
        });
        screen.add(h265Row);

        const pinRow = new Adw.SwitchRow({
            title: 'Require PIN',
            subtitle: 'Prompt for a PIN before a client can mirror',
        });
        pinRow.active = state.pin;
        pinRow.connect('notify::active', () => {
            state.pin = pinRow.active;
            save();
        });
        screen.add(pinRow);

        const restartRow = new Adw.ButtonRow({title: 'Restart receiver to apply'});
        restartRow.connect('activated', () => runCli(['receiver-restart']));
        screen.add(restartRow);

        // --- AirPlay audio receiver (shairport-sync) ---
        const audio = new Adw.PreferencesGroup({
            title: 'AirPlay Receiver (audio)',
            description: 'Receive AirPlay audio. Available when shairport-sync is installed.',
        });
        page.add(audio);

        const audioNameRow = new Adw.EntryRow({title: 'Audio receiver name'});
        audioNameRow.text = state.audioName;
        audioNameRow.connect('changed', () => {
            state.audioName = audioNameRow.text;
            save();
        });
        audio.add(audioNameRow);

        // --- YouTube receiver ---
        const yt = new Adw.PreferencesGroup({
            title: 'YouTube Receiver',
            description: 'Receive casts from phone YouTube / YT-Music apps (needs node + mpv).',
        });
        page.add(yt);

        const ytNameRow = new Adw.EntryRow({title: 'YouTube receiver name'});
        ytNameRow.text = state.ytName;
        ytNameRow.connect('changed', () => {
            state.ytName = ytNameRow.text;
            save();
        });
        yt.add(ytNameRow);

        // --- Casting (outbound) ---
        const casting = new Adw.PreferencesGroup({title: 'Casting'});
        page.add(casting);

        const dropRow = new Adw.SwitchRow({
            title: 'Drop Wi-Fi when casting',
            subtitle: 'Make “Display Cast…” disconnect Wi-Fi by default (needed for Miracast on single-radio adapters)',
        });
        dropRow.active = state.dropWifi;
        dropRow.connect('notify::active', () => {
            state.dropWifi = dropRow.active;
            save();
        });
        casting.add(dropRow);
    }
}
