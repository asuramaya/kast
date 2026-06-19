# Kast

[![ci](https://github.com/asuramaya/kast/actions/workflows/ci.yml/badge.svg)](https://github.com/asuramaya/kast/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/asuramaya/kast?sort=semver)](https://github.com/asuramaya/kast/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`Kast` brings a **Windows `Win+K`-style cast panel** to GNOME on Ubuntu (25.10 / 26.04,
GNOME Shell 49–50) — as a native **Quick Settings tile**. Open the system menu, pick a
target, and cast; control what you're casting to; and receive casts back onto the machine.

Linux has no single upstream stack for AirPlay, Miracast, and Chromecast, so Kast is a **glue
layer**: it wires together the native packages that ship with Ubuntu (plus a couple of
pipx-isolated helpers) and presents them behind one tile, one shortcut, and one CLI.

- **Cast out** — Chromecast / Miracast display (one-click via `gnome-network-displays`),
  AirPlay video (a file or URL to an Apple TV / AirPlay-2 TV via `pyatv`), Chromecast media
  (a file or URL via `catt`), and AirPlay audio out (PipeWire RAOP).
- **Control** — a capability-driven remote (`kast control` + a Control Center window) that
  shows only what the connected device actually supports.
- **Receive in** — AirPlay screen mirroring (`uxplay`), AirPlay audio (`shairport-sync`), and
  YouTube / YT-Music over DIAL (`yt-cast-receiver` + `mpv`). All off by default.
- One **Kast** tile in GNOME Quick Settings, a `kast pick` graphical menu, and a full CLI.

## Scope

**Cast out (this machine → a device):**
- `AirPlay audio out`: yes (PipeWire RAOP)
- `AirPlay video out`: yes for a **file or URL** (`pyatv`); live screen mirroring is not
  included (it needs FairPlay/MFi auth — see Roadmap)
- `Miracast display out`: yes, via `gnome-network-displays` (one-click on ≥ 0.99.0)
- `Chromecast display out`: yes, via `gnome-network-displays` (one-click on ≥ 0.99.0)
- `Chromecast media out`: yes for a **file or URL** (`catt`)

**Receive in (a device → this machine, all off by default):**
- `AirPlay screen receive`: yes, via `uxplay` (PIN-gated when on)
- `AirPlay audio receive`: yes, via `shairport-sync` (AirPlay audio — AirPlay-2 multi-room
  needs a custom build Ubuntu doesn't package)
- `YouTube / YT-Music receive`: yes, via `yt-cast-receiver` + `mpv` (DIAL — no Google auth)
- `Miracast sink`: not included (the only Linux implementation, MiracleCast, is unreliable
  and needs the Wi-Fi radio to itself)
- `Chromecast receive`: not possible (Google Cast requires a device key + Google-signed cert
  a third party cannot obtain)

**Control:** capability-driven (`kast control` / the Control Center window) — an AirPlay-only
TV exposes stop + volume, an Apple TV the full remote (transport, nav, power, now-playing).

## One-Line Install

Remote (downloads the latest release, then installs):

```bash
curl -fsSL https://raw.githubusercontent.com/asuramaya/kast/main/install.sh | bash
```

From a clone:

```bash
git clone https://github.com/asuramaya/kast
cd kast
./install.sh
```

The core install stays lean. The heavier inbound receivers are opt-in:

```bash
./install.sh --with-airplay-audio   # shairport-sync (AirPlay audio receive)
./install.sh --with-youtube         # nodejs/npm/mpv/yt-dlp (YouTube receive)
./install.sh --with-all             # everything
```

Other flags: `--skip-apt` (don't touch apt), `--no-shortcut`, `--shortcut '<Primary>k'`.
After installing, run `kast doctor` to confirm the stack is healthy.

## What The Installer Does

1. Installs the core Ubuntu packages in [packages.txt](packages.txt) (discovery, casting out,
   AirPlay screen receive, the picker) — plus any opt-in receiver deps you requested.
2. Enables PipeWire RAOP discovery with [50-raop.conf](config/pipewire/50-raop.conf).
3. Installs the `kast` CLI and its helpers (`kast-airplay`, `kast-control-center`) into
   `~/.local/bin`.
4. Installs the receiver services — `uxplay`, `shairport-sync`, `kast-youtube` — all left
   **off** by default (they're LAN listeners).
5. Installs and enables the GNOME Quick Settings extension (the Kast tile + preferences).
6. Adds a GNOME app launcher and a default `Super+K` shortcut (both open `kast pick`).
7. Installs `pyatv` (AirPlay video out + control) and `catt` (Chromecast media) isolated via
   `pipx`, and the YouTube receiver's Node deps when `--with-youtube` is set.

> **Log out and back in** after installing — Wayland can't hot-reload shell extensions,
> so the Kast tile appears in Quick Settings only on your next login. Until then (or on any
> GNOME version the tile doesn't support), `kast pick` / `Super+K` give you the cast menu.

## Updating

```bash
kast check-update    # is a newer release available?
kast update          # update in place from the latest GitHub release
kast update --apt    # also refresh system (apt) packages for your installed features
```

`kast update` re-runs the installer for the latest release, preserving the optional features
you already have (it detects shairport-sync / the YouTube receiver and keeps them). By default
it doesn't touch apt (so it needs no `sudo` and works from the tile's one-click "⬆ Update"
entry); use `--apt` from a terminal to also refresh system packages. The `curl | bash`
bootstrap verifies the downloaded release tarball against its published `.sha256` before
extracting (and aborts on mismatch); the `.sha256` is also there for manual verification.

## Uninstall

```bash
./uninstall.sh            # remove kast (keeps your config)
./uninstall.sh --purge    # also remove ~/.config/kast and state
```

Apt packages are left installed (they are shared system components). The pipx tools can be
removed with `pipx uninstall pyatv` / `pipx uninstall catt`.

## Quick Settings tile

Open the system menu (top-right); the **Kast** tile sits next to Wi-Fi/Bluetooth. Clicking the
tile opens the graphical picker; the ⌄ expands a lean menu built around collapsible groups:

- **Casting · &lt;target&gt;** + **Disconnect** — shown only while a stream is live.
- **Cast to…** *(collapsible)* — discovered Chromecast (mirror / cast-file), AirPlay video
  (cast-file), and, after a scan, Miracast targets; plus **Open picker…**, **Scan for
  Miracast**, and **Rescan**.
- **Receive** *(collapsible)* — on/off switches for the AirPlay screen, AirPlay audio, and
  YouTube receivers (audio/YouTube shown only when their deps are installed).
- **Control Center…** — opens the full remote window for a controllable device.
- **Kast Settings…** — the preferences dialog (all configuration lives here).
- The installed version and an **⬆ Update** entry when one is available.

Configuration (receiver names, mirror mode, H.265, PIN, Wi-Fi behaviour) lives in
**preferences**, not the tile; audio-output routing is left to GNOME's native Sound menu.

### Control Center

`kast control-center [target]` (or the tile's **Control Center…**) opens a GTK4/Adwaita remote
that renders only the controls the device reports — now-playing, transport, a volume slider, a
d-pad, and power. From the CLI, `kast control` lists controllable devices and
`kast control <target> <action>` runs one action (stop / play / pause / volume / power / key …).

### Preferences

**Kast Settings…** (or `gnome-extensions prefs kast@asuramaya`) opens an Adwaita dialog for the
receiver names, mirror/overlay mode, H.265, require-PIN, and the default "drop Wi-Fi when
casting" behaviour. It writes `~/.config/kast/uxplay.conf` — the same file the CLI reads.

## CLI

```
kast pick [--miracast]                 graphical "cast to…" menu (Super+K / launcher)
kast targets [--json] [--scan]         every discovered target (Chromecast + AirPlay)
                                       --scan issues fresh mDNS queries (vs the avahi cache)
kast connect <name|addr> [media]       connect: mirror, or cast a file/URL if given
kast cast-file <target> <url|file>     play a file/URL (AirPlay via pyatv, Chromecast via catt)
kast disconnect                        stop the active display stream
kast control [<target> [<action>]]     control center (caps / now-playing / actions)
kast control-center [target]           the graphical remote window
kast airplay-targets / cast-targets / miracast-targets [--json] [--scan]
kast receiver-start|stop|toggle              AirPlay screen receiver (uxplay)
kast audio-receiver-start|stop|toggle        AirPlay audio receiver (shairport-sync)
kast youtube-receiver-start|stop|toggle      YouTube DIAL receiver
kast status [--json]   kast doctor   kast repair   kast check-update   kast update [--apt]
```

`kast doctor` runs a full health check (tools, discovery, receivers, casting, desktop
integration) and prints a fix hint per problem. `kast repair` reinstalls the pipx helpers if a
Python/OS upgrade breaks their venvs.

If you want `Ctrl+K` instead of `Super+K`: `KAST_SHORTCUT='<Primary>k' ./install.sh`.

## Repo Layout

- [install.sh](install.sh): bootstrap entrypoint (self-bootstraps when piped from curl)
- [uninstall.sh](uninstall.sh): symmetric uninstaller (`--purge` also removes config/state)
- [scripts/kast](scripts/kast): runtime CLI; the extension shells out to `kast … --json`
- [scripts/kast-airplay](scripts/kast-airplay): Python helper driving `pyatv` (AirPlay out + control)
- [scripts/kast-control-center](scripts/kast-control-center): GTK4/Adwaita Control Center window
- [youtube-receiver/](youtube-receiver): the Node DIAL receiver (`yt-cast-receiver` + `mpv`)
- [shell-extension/kast@asuramaya/](shell-extension/kast@asuramaya): the Quick Settings UI (`extension.js` tile + `prefs.js` dialog)
- [systemd/user/](systemd/user): the off-by-default receiver services (uxplay / shairport-sync / kast-youtube)

## Configuration

Copy and edit [config/uxplay.conf.example](config/uxplay.conf.example); the installed copy lives
at `~/.config/kast/uxplay.conf` (also editable from the preferences dialog). You can set the
receiver names, extra `uxplay` flags (e.g. `-h265`, `-pin`), and the default Wi-Fi behaviour.

## Troubleshooting

Run `kast doctor` first — it checks tools, discovery, the receivers, outbound casting, audio
routing, and desktop integration, and prints a fix hint for each problem.

- **`kast: command not found`** — `~/.local/bin` isn't on your `PATH`. Add it, or log out/in.
- **No Kast tile in Quick Settings** — the extension loads only after a fresh login on Wayland.
  Log out/in, then check `gnome-extensions list --enabled | grep kast` and `kast doctor`.
- **Tile gone after a GNOME/Ubuntu upgrade** — a new GNOME Shell can flag the extension "out of
  date" (`kast doctor` reports this). `kast update` for metadata that supports the new shell,
  then log out/in. Meanwhile `kast pick` / `Super+K` give the cast menu without the tile.
- **No Miracast displays found** — discovery is an on-demand Wi-Fi P2P find; some adapters can't
  do P2P at all (`kast doctor` reports this). Try again near the display.
- **AirPlay/Chromecast video cast fails** — run `kast doctor`; if it reports a broken pyatv/catt
  venv (common after an OS/Python upgrade), run `kast repair`. If an AirPlay TV rejects the cast,
  pair it once with `kast airplay-pair <target>`.
- **YouTube receiver toggle missing** — it needs `node` + `mpv`; install with
  `./install.sh --with-youtube` (then log out/in).

## Security

`kast` runs entirely in your user session — there is no privileged daemon. Worth knowing:

- **The receivers are off by default.** They're LAN-facing listeners (`uxplay`, `shairport-sync`,
  the YouTube DIAL receiver) — turn one on only while receiving, off when done. The AirPlay
  screen receiver is **PIN-gated** when on, but the PIN is a 4-digit speed bump, not strong
  auth, and doesn't protect uxplay's parser. Off-when-idle is the real control.
- Casting connects via `gnome-network-displays` (its D-Bus daemon, or its GUI as a fallback) and
  `pyatv`/`catt`; discovered device names are attacker-controlled and only ever reach `jq`/labels
  as text (avahi escapes are decoded but control bytes are refused).
- `~/.config/kast/uxplay.conf` is sourced by the CLI (like a shell rc file); the preferences
  dialog escapes everything it writes there.
- `install.sh` and `kast update` fetch over HTTPS from GitHub; the `curl | bash` bootstrap
  verifies the release tarball against its published `.sha256` before extracting and aborts on a
  mismatch (the unreviewed main-branch fallback is inherently unverifiable and warns loudly —
  refuse it with `KAST_NO_UNSTABLE=1`). yt-dlp downloads are SHA-256 verified too. The pipx
  helpers are isolated per-tool.

Found a vulnerability? Please report it privately via the repository's **Security** tab —
details in [SECURITY.md](SECURITY.md).

## Status & Roadmap

Real today: one-click Chromecast/Miracast connect (gnd D-Bus daemon, GUI fallback), AirPlay
video-out and Chromecast media-out (file/URL), the capability-driven control center, three
off-by-default inbound receivers (AirPlay screen/audio, YouTube DIAL), the unified
`targets`/`connect`/`cast-file`/`pick` surface, the redesigned Quick Settings tile + preferences,
GNOME 49–50 support, and tiered/self-healing dependencies.

Known limitations:

- One-click display connect needs `gnome-network-displays` **≥ 0.99.0** (ships the D-Bus daemon;
  Ubuntu 26.04 has it). On older versions Kast falls back to the GUI picker. Kast installs a D-Bus
  activation file so the session bus starts the daemon on demand, with a runtime fallback that
  spawns it directly if activation isn't available.
- Live **screen** mirroring out goes to Chromecast/Miracast via `gnome-network-displays`
  (the tile's "mirror screen"); the `pyatv`/`catt` **file-or-URL** cast is a separate path, and
  AirPlay screen mirroring out is not possible (FairPlay/MFi — see below).
- Discovery is mDNS for Chromecast/AirPlay: cheap cached reads keep the UI responsive, and the tile
  refreshes with fresh queries periodically in the background and when you open "Cast to…" (the
  `kast pick` picker always scans actively, behind a progress dialog). `--scan` forces fresh queries
  from the CLI. Miracast is an on-demand Wi-Fi P2P find (shares the radio), so it's never auto-polled.
- The YouTube receiver depends on `yt-dlp`; Kast keeps a self-updating user-local copy (refreshed
  daily) and points mpv at it, so YouTube changes heal without an apt upgrade. Needs `curl` to
  fetch it; a system `yt-dlp` is used as a fallback.

Out of scope: **AirPlay live screen mirroring out** (needs FairPlay/MFi auth — the only Linux
sender, `doubletake`, runs extracted Apple code and is too new/licensing-fraught to bundle);
**Miracast sink** and **Chromecast receive** (see Scope).
