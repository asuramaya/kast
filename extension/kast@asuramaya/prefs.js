import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const CONF_DIR = GLib.build_filenamev([GLib.get_user_config_dir(), 'kast']);
const CONF_PATH = GLib.build_filenamev([CONF_DIR, 'uxplay.conf']);
const CLI_PATH = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'kast']);

// The CLI computes a host-qualified default name at runtime whenever the conf
// doesn't set one. We mirror those defaults so prefs shows the same value, and
// so we only persist a name line when the user actually customizes it (writing
// the literal would otherwise freeze the name to the hostname-at-save-time).
const HOST = (GLib.get_host_name() || '').split('.')[0];
const SUFFIX = HOST ? ` (${HOST})` : '';
const DEFAULT_NAMES = {
    UXPLAY_NAME: `Kast Receiver${SUFFIX}`,
    SHAIRPORT_NAME: `Kast Audio${SUFFIX}`,
    YT_RECEIVER_NAME: `Kast YouTube${SUFFIX}`,
};

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
    // Show the CLI's host-qualified default when the conf doesn't set a name.
    const name = (text.match(/UXPLAY_NAME="([^"]*)"/) || [, DEFAULT_NAMES.UXPLAY_NAME])[1];
    const audioName = (text.match(/SHAIRPORT_NAME="([^"]*)"/) || [, DEFAULT_NAMES.SHAIRPORT_NAME])[1];
    const ytName = (text.match(/YT_RECEIVER_NAME="([^"]*)"/) || [, DEFAULT_NAMES.YT_RECEIVER_NAME])[1];
    const argsRaw = (text.match(/UXPLAY_ARGS=\(([^)]*)\)/) || [, ''])[1];
    const tokens = argsRaw.trim().split(/\s+/).filter(t => t.length > 0);
    const pinIdx = tokens.indexOf('-pin');
    const pinCode = (pinIdx >= 0 && /^\d+$/.test(tokens[pinIdx + 1] || '')) ? tokens[pinIdx + 1] : '';
    return {
        name,
        audioName,
        ytName,
        tokens,
        h265: tokens.includes('-h265'),
        pin: pinIdx >= 0,
        pinCode,
        dropWifi: /KAST_DROP_WIFI_DEFAULT=1/.test(text),
    };
}

// Rebuild UXPLAY_ARGS, preserving any custom flags the user added by hand while
// toggling the ones we manage (-h265, -pin and its optional numeric value).
function buildArgs(tokens, {h265, pin, pinCode}) {
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
    if (pin) {
        // Bare -pin makes uxplay show a random PIN on the receiving screen each
        // time; "-pin <digits>" pins a fixed code the user can hand out.
        out.push('-pin');
        if (/^\d+$/.test(pinCode || ''))
            out.push(pinCode);
    }
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

// Upsert a `KEY=...` assignment in the conf text, replacing the existing line if
// present or appending otherwise. Preserves comments and any unmanaged lines
// (e.g. a hand-set SHAIRPORT_ARGS), so a prefs save never silently drops them.
function upsertAssign(text, key, line) {
    const re = new RegExp(`^${key}=.*$`, 'm');
    if (re.test(text))
        return text.replace(re, line);
    return `${text.replace(/\n*$/, '\n')}${line}\n`;
}

function removeAssign(text, key) {
    return text.replace(new RegExp(`^${key}=.*\\n?`, 'm'), '');
}

function writeConf(state) {
    let text = '';
    try {
        const [ok, bytes] = GLib.file_get_contents(CONF_PATH);
        if (ok)
            text = new TextDecoder().decode(bytes);
    } catch (_e) {
        // No existing conf — start from a documented header below.
    }
    if (!text.trim()) {
        text = '# shellcheck shell=bash\n' +
            '# Managed by Kast preferences. Lines not shown are preserved on save.\n\n';
    }

    const args = buildArgs(state.tokens, state).filter(safeToken);
    text = upsertAssign(text, 'UXPLAY_ARGS', `UXPLAY_ARGS=(${args.join(' ')})`);
    text = upsertAssign(text, 'KAST_DROP_WIFI_DEFAULT', `KAST_DROP_WIFI_DEFAULT=${state.dropWifi ? 1 : 0}`);

    // Names: persist a line only when the user customized it (differs from the
    // host-qualified default). Otherwise drop the line so the CLI keeps computing
    // the dynamic default — which stays correct if the box is later renamed.
    for (const [key, value] of [
        ['UXPLAY_NAME', state.name],
        ['SHAIRPORT_NAME', state.audioName],
        ['YT_RECEIVER_NAME', state.ytName],
    ]) {
        const clean = sanitizeName(value);
        if (clean && clean !== DEFAULT_NAMES[key])
            text = upsertAssign(text, key, `${key}="${clean}"`);
        else
            text = removeAssign(text, key);
    }

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

        const fullscreenRow = new Adw.SwitchRow({
            title: 'Fullscreen',
            subtitle: 'Show the received screen fullscreen instead of in a window',
        });
        fullscreenRow.active = getMode() === 'video-overlay';
        fullscreenRow.connect('notify::active', () => {
            runCli(['set-mode', fullscreenRow.active ? 'video-overlay' : 'mirror']);
        });
        screen.add(fullscreenRow);

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
            subtitle: 'A sender must enter a PIN before it can mirror',
        });
        pinRow.active = state.pin;
        screen.add(pinRow);

        // Optional fixed PIN. Left blank, uxplay shows a fresh random 4-digit
        // PIN on the receiving screen for each connection; set one here to hand
        // out a code instead.
        const pinCodeRow = new Adw.EntryRow({
            title: 'PIN code (blank = random, shown on screen)',
        });
        pinCodeRow.text = state.pinCode;
        pinCodeRow.set_sensitive(state.pin);
        pinCodeRow.connect('changed', () => {
            // uxplay PINs are 4 digits; keep only those, ignore the rest.
            const digits = pinCodeRow.text.replace(/\D/g, '').slice(0, 4);
            if (digits !== pinCodeRow.text) {
                pinCodeRow.text = digits;
                return; // re-enters with the cleaned value, which saves below
            }
            state.pinCode = digits;
            save();
        });
        screen.add(pinCodeRow);

        pinRow.connect('notify::active', () => {
            state.pin = pinRow.active;
            pinCodeRow.set_sensitive(pinRow.active);
            save();
        });

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
