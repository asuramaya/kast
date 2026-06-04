// kast YouTube DIAL receiver.
//
// yt-cast-receiver advertises the box over DIAL/SSDP and runs the whole cast
// control session (play/pause/seek/queue) — a phone's YouTube / YT-Music app
// finds it with no pairing and no Google Cast auth. We only implement a Player:
// resolve a video id and drive mpv, which plays the stream via its bundled
// yt-dlp hook. No login is needed for public videos.
//
// Env: KAST_YT_NAME (advertised name), KAST_YT_MPV (mpv binary), KAST_YT_PORT,
// KAST_YT_DLP (yt-dlp binary for mpv's ytdl_hook; kast keeps it self-updated).
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
const SOCK = path.join(os.tmpdir(), `kast-mpv-${process.pid}.sock`);
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
    await fs.writeFile(this._file, JSON.stringify(this._data));
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
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    const opts = startSec ? `start=+${Math.floor(startSec)}` : '';
    await this.cmd('loadfile', url, 'replace', opts ? { 'start': `+${Math.floor(startSec)}` } : {});
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

const receiver = new YouTubeCastReceiver(new MpvPlayer(), {
  dial: { port: PORT },
  device: { name: NAME, brand: 'Kast', model: 'kast' },
  app: { enableAutoplayOnConnect: true },
  dataStore: new FileDataStore(path.join(STATE_DIR, 'youtube-receiver.json')),
});

receiver.on('error', (err) => console.error('kast-youtube:', err?.message || err));

process.on('SIGTERM', async () => { try { await receiver.stop(); } catch {} process.exit(0); });
process.on('SIGINT', async () => { try { await receiver.stop(); } catch {} process.exit(0); });

await receiver.start();
console.log(`kast YouTube receiver "${NAME}" advertising on DIAL port ${PORT}`);
