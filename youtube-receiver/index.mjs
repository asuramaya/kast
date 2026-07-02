// kast YouTube DIAL receiver.
//
// yt-cast-receiver advertises the box over DIAL/SSDP and runs the whole cast
// control session (play/pause/seek/queue) — a phone's YouTube / YT-Music app
// finds it with no pairing and no Google Cast auth. We only implement a Player:
// resolve a video id and drive mpv, which plays the stream via its bundled
// yt-dlp hook. No login is needed for public videos.
//
// Env: KAST_YT_NAME (advertised name), KAST_YT_MPV (mpv binary), KAST_YT_PORT,
// KAST_YT_DLP (yt-dlp binary for mpv's ytdl_hook; kast keeps it self-updated),
// KAST_YT_AUTOPLAY (=1 lets a bare DIAL connect start playback; off otherwise).
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import YouTubeCastReceiver, { Player, DataStore } from 'yt-cast-receiver';

const NAME = process.env.KAST_YT_NAME || 'Kast YouTube';
const MPV = process.env.KAST_YT_MPV || 'mpv';
const YTDLP = process.env.KAST_YT_DLP || '';
const PORT = parseInt(process.env.KAST_YT_PORT || '8009', 10);
const AUTOPLAY = process.env.KAST_YT_AUTOPLAY === '1';
// mpv's JSON-IPC socket must NOT live in shared /tmp: anyone who can open it
// speaks full mpv IPC (load local files, screenshot to arbitrary paths, drive
// playback, read state). Keep it in a private 0700 dir, preferring the per-uid
// XDG_RUNTIME_DIR (already 0700) over a tmpdir fallback.
const SOCK_DIR = path.join(process.env.XDG_RUNTIME_DIR || os.tmpdir(), 'kast');
const SOCK = path.join(SOCK_DIR, `mpv-${process.pid}.sock`);
// YouTube ids are exactly 11 chars of [A-Za-z0-9_-]; the cast payload is
// unauthenticated (DIAL), so validate before building any URL from a video id.
const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;
// Cap the IPC read buffer so a peer streaming bytes with no newline can't grow
// it without bound (memory-exhaustion DoS). mpv replies are tiny.
const MAX_IPC_BUF = 1 << 20;
const STATE_DIR = process.env.KAST_YT_STATE
  || path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state'), 'kast');

// A JSON-file DataStore. The library's DefaultDataStore hard-codes node-persist
// with no configurable directory and races its own async init(), so we provide
// our own — set/get persisted to one file under XDG_STATE.
class FileDataStore extends DataStore {
  constructor(file) {
    super();
    this._file = file;
    this._data = null;
  }
  async _load() {
    if (this._data) return;
    try { this._data = JSON.parse(await fs.readFile(this._file, 'utf8')); }
    catch { this._data = {}; }
  }
  async set(key, value) {
    await this._load();
    this._data[key] = value;
    await fs.mkdir(path.dirname(this._file), { recursive: true });
    // Write+rename so a crash mid-write can't truncate the file (which would
    // reset persisted screen/pairing state to {} on the next load).
    const tmp = `${this._file}.${process.pid}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(this._data));
    await fs.rename(tmp, this._file);
  }
  async get(key) {
    await this._load();
    return key in this._data ? this._data[key] : null;
  }
}

// Minimal mpv JSON-IPC client: one long-lived idle mpv, commands over a unix
// socket, request/response for get_property. mpv plays YouTube URLs directly
// through its ytdl_hook (yt-dlp), so we never resolve stream URLs ourselves.
class Mpv {
  constructor() {
    this._proc = null;
    this._sock = null;
    this._reqId = 0;
    this._pending = new Map();
    this._buf = '';
  }

  async _ensure() {
    if (this._proc && !this._proc.killed) return;
    // Private dir for the IPC socket (0700), and clear any stale socket left by
    // a prior crash before mpv recreates it.
    await fs.mkdir(SOCK_DIR, { recursive: true, mode: 0o700 });
    try { await fs.rm(SOCK, { force: true }); } catch { /* ignore */ }
    const args = [
      '--idle=yes', '--force-window=yes', '--keep-open=no',
      '--no-terminal', `--input-ipc-server=${SOCK}`,
    ];
    // Point mpv's ytdl_hook at kast's self-updating yt-dlp when provided.
    if (YTDLP) args.push(`--script-opts=ytdl_hook-ytdl_path=${YTDLP}`);
    this._proc = spawn(MPV, args, { stdio: 'ignore' });
    this._proc.on('exit', () => { this._proc = null; this._sock = null; });
    await this._connect();
  }

  _connect() {
    return new Promise((resolve, reject) => {
      const tryOnce = (left) => {
        const s = net.connect(SOCK);
        s.on('connect', () => {
          this._sock = s;
          s.on('data', (d) => this._onData(d));
          s.on('error', () => {});
          resolve();
        });
        s.on('error', () => {
          if (left <= 0) return reject(new Error('mpv IPC connect failed'));
          setTimeout(() => tryOnce(left - 1), 200);
        });
      };
      tryOnce(25);
    });
  }

  _onData(chunk) {
    this._buf += chunk.toString('utf8');
    if (this._buf.length > MAX_IPC_BUF) {
      // Runaway input with no newline — drop it rather than grow unbounded.
      this._buf = '';
      return;
    }
    let nl;
    while ((nl = this._buf.indexOf('\n')) >= 0) {
      const line = this._buf.slice(0, nl);
      this._buf = this._buf.slice(nl + 1);
      if (!line.trim()) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.request_id != null && this._pending.has(msg.request_id)) {
        const { resolve } = this._pending.get(msg.request_id);
        this._pending.delete(msg.request_id);
        resolve(msg.error === 'success' ? msg.data : null);
      }
    }
  }

  async cmd(...command) {
    await this._ensure();
    return new Promise((resolve) => {
      const request_id = ++this._reqId;
      this._pending.set(request_id, { resolve });
      this._sock.write(JSON.stringify({ command, request_id }) + '\n');
      setTimeout(() => {
        if (this._pending.has(request_id)) {
          this._pending.delete(request_id);
          resolve(null);
        }
      }, 3000);
    });
  }

  async load(videoId, startSec) {
    await this._ensure();
    if (!VIDEO_ID_RE.test(videoId))
      throw new Error(`refusing to play invalid video id: ${JSON.stringify(videoId)}`);
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    // Apply the start offset via the per-file `start` property (set before the
    // load takes effect) rather than a positional loadfile option — the latter
    // changed arg position across mpv versions; the property is stable.
    await this.cmd('set_property', 'start',
      startSec && startSec > 0 ? `+${Math.floor(startSec)}` : 'none');
    await this.cmd('loadfile', url, 'replace');
  }

  stop() { return this.cmd('stop'); }
  setPause(p) { return this.cmd('set_property', 'pause', p); }
  seek(sec) { return this.cmd('seek', sec, 'absolute'); }
  setVolume(v) { return this.cmd('set_property', 'volume', v); }
  async getVolume() { const v = await this.cmd('get_property', 'volume'); return v == null ? 50 : Math.round(v); }
  async getPosition() { const v = await this.cmd('get_property', 'time-pos'); return v == null ? 0 : Math.round(v); }
  async getDuration() { const v = await this.cmd('get_property', 'duration'); return v == null ? 0 : Math.round(v); }

  quit() {
    try { this._sock?.end(); } catch {}
    try { this._proc?.kill(); } catch {}
    this._proc = null; this._sock = null;
  }
}

class MpvPlayer extends Player {
  constructor() {
    super();
    this._mpv = new Mpv();
  }

  async doPlay(video, position) {
    await this._mpv.load(video.id, position);
    await this._mpv.setPause(false);
    return true;
  }
  async doPause() { await this._mpv.setPause(true); return true; }
  async doResume() { await this._mpv.setPause(false); return true; }
  async doStop() { await this._mpv.stop(); return true; }
  async doSeek(position) { await this._mpv.seek(position); return true; }
  async doSetVolume(volume) { await this._mpv.setVolume(volume.level ?? volume); return true; }
  async doGetVolume() { const level = await this._mpv.getVolume(); return { level, muted: false }; }
  async doGetPosition() { return this._mpv.getPosition(); }
  async doGetDuration() { return this._mpv.getDuration(); }
}

const player = new MpvPlayer();
const receiver = new YouTubeCastReceiver(player, {
  dial: { port: PORT },
  device: { name: NAME, brand: 'Kast', model: 'kast' },
  // Autoplay-on-connect lets any device that reaches the DIAL port start playback
  // unsolicited — DIAL has no pairing, so that's the whole LAN. Ships off; opt in
  // with KAST_YT_AUTOPLAY=1 in uxplay.conf on a trusted network.
  app: { enableAutoplayOnConnect: AUTOPLAY },
  dataStore: new FileDataStore(path.join(STATE_DIR, 'youtube-receiver.json')),
});

receiver.on('error', (err) => console.error('kast-youtube:', err?.message || err));

// Node doesn't forward signals to the spawned mpv, so kill it explicitly —
// otherwise every restart leaks an mpv process, window, and stale IPC socket.
async function shutdown() {
  try { await receiver.stop(); } catch { /* ignore */ }
  try { player._mpv.quit(); } catch { /* ignore */ }
  process.exit(0);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await receiver.start();
console.log(`kast YouTube receiver "${NAME}" advertising on DIAL port ${PORT}`);
