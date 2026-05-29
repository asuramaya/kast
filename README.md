# Kast

[![ci](https://github.com/asuramaya/kast/actions/workflows/ci.yml/badge.svg)](https://github.com/asuramaya/kast/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/asuramaya/kast?sort=semver)](https://github.com/asuramaya/kast/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`Kast` is a one-line Ubuntu setup that brings a **Windows `Win+K`-style cast panel** to
GNOME on Ubuntu 25.10 — as a native **Quick Settings tile**. Open the system menu, pick a
target, cast — and route audio to AirPlay speakers, all from the same panel as Wi-Fi/BT.

It is not a single protocol-unified backend. Linux has no one upstream stack for AirPlay,
Miracast, and Chromecast, so Kast wires together the native packages that already ship in
Ubuntu 25.10 and presents them behind one Quick Settings tile and one shortcut.

- Outbound AirPlay audio via PipeWire RAOP
- Outbound AirPlay **video** (a file or URL to an Apple TV / AirPlay-2 TV) via `pyatv`
- Outbound Miracast and Chromecast display casting via `gnome-network-displays` —
  **one-click connect** when its D-Bus daemon (≥ 0.99.0) is present
- Inbound AirPlay receiver mode via `uxplay`
- A single **Kast** tile in GNOME Quick Settings: cast targets, the AirPlay receiver toggle,
  sink selection, and mirror/overlay mode, plus a preferences dialog

## Scope

**Out (this machine → a device):**
- `AirPlay audio out`: yes (PipeWire RAOP)
- `AirPlay video out`: yes for a **file or URL** (`pyatv`); live screen mirroring is not
  included (it needs FairPlay/MFi auth — see Roadmap)
- `Miracast display out`: yes, through `gnome-network-displays` (one-click on ≥ 0.99.0)
- `Chromecast display out`: yes, through `gnome-network-displays` (one-click on ≥ 0.99.0)

**In (a device → this machine):**
- `AirPlay screen receive`: yes, through `uxplay` (off by default; PIN-gated when on)
- `AirPlay audio receive`: yes, through `shairport-sync` (off by default; AirPlay audio —
  AirPlay-2 multi-room needs a custom build Ubuntu doesn't package)
- `Miracast sink (receive)`: not included — the only Linux implementation (MiracleCast) is
  unreliable on current setups and needs the Wi-Fi radio to itself
- `Chromecast receive`: not possible — Google Cast requires a device key + Google-signed cert
  a third party cannot obtain

**Control:**
- `Remote control` of a connected device: capability-driven (`kast control` /
  Control Center) — what's offered depends on what the device reports (an AirPlay-only TV
  exposes stop + volume, an Apple TV the full remote)

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

Flags: `--skip-apt` (don't touch apt), `--no-shortcut`, `--shortcut '<Primary>k'`.
After installing, run `kast doctor` to confirm the stack is healthy.

## What The Installer Does

1. Installs the native Ubuntu packages listed in [packages.txt](packages.txt).
2. Enables PipeWire RAOP discovery with [50-raop.conf](config/pipewire/50-raop.conf).
3. Installs the `kast` CLI and its `kast-airplay` helper into `~/.local/bin`.
4. Installs the `uxplay` receiver service (left **off** by default — it's a LAN listener).
5. Installs and enables the GNOME Quick Settings extension (the Kast tile + preferences).
6. Adds a GNOME app launcher and a default `Super+K` shortcut.
7. Installs `pyatv` via `pipx` if present (optional; powers AirPlay video out).

> **Log out and back in** after installing — Wayland can't hot-reload shell extensions,
> so the Kast tile appears in Quick Settings only on your next login.

## Updating

```bash
kast check-update    # is a newer release available?
kast update          # update in place from the latest GitHub release
```

The Kast tile also checks periodically and surfaces an "⬆ Update to vX.Y.Z" entry when one
is available — clicking it runs the update for you.

## Uninstall

```bash
./uninstall.sh            # remove kast (keeps your config)
./uninstall.sh --purge    # also remove ~/.config/kast and state
```

Apt packages are left installed (they are shared system components).

## Repo Layout

- [install.sh](install.sh): bootstrap entrypoint (self-bootstraps when piped from curl)
- [uninstall.sh](uninstall.sh): symmetric uninstaller (`--purge` also removes config/state)
- [scripts/kast](scripts/kast): runtime CLI; the extension shells out to `kast … --json`
- [scripts/kast-airplay](scripts/kast-airplay): Python helper that drives `pyatv` for AirPlay video out
- [shell-extension/kast@asuramaya/](shell-extension/kast@asuramaya): the GNOME Quick Settings UI (`extension.js` tile + `prefs.js` dialog)
- [systemd/user/uxplay.service](systemd/user/uxplay.service): AirPlay receiver (uses `uxplay -fs` for video-overlay mode)

## Default UX

- A Kast tile in the GNOME Quick Settings menu (top-right), next to Wi-Fi/BT
- `Super+K` (the `Win+K` equivalent) and the app launcher open **`kast pick`**, a graphical
  "cast to…" menu that works even if the tile isn't loaded
- `kast status` shows stack status; `kast doctor` runs a full health check
- `kast targets` lists everything castable (Chromecast + AirPlay); `kast connect <name>`
  connects, `kast disconnect` stops
- `kast cast-targets` lists Chromecast / Google Cast devices discovered on the LAN (mDNS)
- `kast miracast-targets` scans for Wi-Fi Display (Miracast) sinks on demand
- `kast airplay-targets` lists AirPlay video receivers; `kast airplay-cast <target> <file|url>`
  casts a video to one (`kast airplay-pair <target>` first if it requires a code)
- `kast select-airplay` switches the default sink to the first discovered AirPlay output
- `kast select-local` returns audio to a local sink

If you actually want `Ctrl+K` instead of `Super+K`, install with:

```bash
KAST_SHORTCUT='<Primary>k' ./install.sh
```

## Configuration

Copy and edit:

- [config/uxplay.conf.example](config/uxplay.conf.example)

Installed location:

- `~/.config/kast/uxplay.conf`

You can set:

- Receiver name
- Extra `uxplay` flags such as `-h265` or `-pin`

## Quick Settings tile

Open the system menu (top-right). One **Kast** tile sits alongside Wi-Fi/Bluetooth. Click
the tile to open the display picker; the ⌄ expands a native menu with two sections:

- **Cast** — discovered **Chromecast** targets (+ rescan) and **Miracast** displays, each of
  which **connects in one click**; discovered **AirPlay video** receivers, each with a
  **cast file…** action (opens a file chooser) and a **pair…** action (for code-protected
  TVs); plus the manual **Display Cast…** / **Miracast (drops Wi-Fi)…** picker actions and an
  on-demand **Scan for Miracast displays**. While a stream is live the tile shows
  **Casting · &lt;target&gt;** and a **Disconnect** entry.
- **Receiver** — an **AirPlay Receiver** on/off switch, mirror/overlay **Mode**, **AirPlay
  output** sinks (+ Use Local Speakers), and **Restart Receiver**. The receiver is **off by
  default** (it's a LAN-facing listener) — flip the switch on to receive; it's PIN-gated when
  on, and PIN is only a 4-digit speed bump, so turn it back off when you're done.

Below that: **Sound/Display Settings…**, **Kast Settings…** (the preferences dialog), and the
version / update entry.

Clicking a discovered Chromecast/Miracast connects via the `gnome-network-displays` daemon
when it's present (≥ 0.99.0); otherwise Kast opens its picker to finish the connection.

### Preferences

**Kast Settings…** (or `gnome-extensions prefs kast@asuramaya`) opens an Adwaita dialog for
the receiver name, H.265, require-PIN, and the default "drop Wi-Fi when casting" behaviour.
It writes `~/.config/kast/uxplay.conf` — the same file the CLI reads.

## Troubleshooting

Run `kast doctor` first — it checks tools, discovery, the receiver, outbound casting, audio
routing, and desktop integration, and prints a fix hint for each problem.

- **`kast: command not found`** — `~/.local/bin` isn't on your `PATH`. Add it to your shell
  profile, or log out and back in.
- **No Kast tile in Quick Settings** — the extension loads only after a fresh login on
  Wayland. Log out/in, then check `gnome-extensions list --enabled | grep kast` and
  `kast doctor`. Enable manually with `gnome-extensions enable kast@asuramaya`.
- **Tile gone after a GNOME/Ubuntu upgrade** — a new GNOME Shell can flag the extension
  "out of date" (`kast doctor` reports this). Update kast (`kast update`) for metadata that
  supports the new shell, then log out/in. In the meantime, **`kast pick`** (the launcher /
  `Super+K`) gives you the same cast menu without the tile.
- **No Miracast displays found** — discovery is an on-demand Wi-Fi P2P find; some adapters
  can't do P2P at all (`kast doctor` reports this). Try again near the display.
- **Chromecast cast drops the network** — fixed in the default action; only the explicit
  *Miracast (drops Wi-Fi)* item disconnects Wi-Fi. Use **Display Cast…** for Chromecast.
- **AirPlay sinks don't appear** — confirm the RAOP config is installed (`kast doctor`) and
  the speaker is on the same network.
- **AirPlay video cast fails** — run `kast doctor`; if it reports the pyatv venv is broken
  (common after an OS/Python upgrade), run `pipx reinstall pyatv`. If the TV rejects the cast,
  pair it once with `kast airplay-pair <target>`.

## Security

`kast` runs entirely in your user session — there is no privileged daemon. Worth knowing:

- **The AirPlay receiver is off by default.** It's a LAN-facing listener (`uxplay`) that
  parses untrusted media, so turn it on (from the Kast tile) only while receiving, and off
  when done. When on it is **PIN-gated**, but the PIN is a 4-digit speed bump — not strong
  authentication, and it does not protect uxplay's parser. Off-when-idle is the real control.
- Casting only **discovers** devices (Chromecast via mDNS, Miracast via Wi-Fi P2P) and never
  auto-connects; selecting one hands off to `gnome-network-displays`. Discovered device names
  are treated as untrusted and only ever reach `jq`/labels as text.
- `~/.config/kast/uxplay.conf` is sourced by the CLI (like a shell rc file); the preferences
  dialog escapes everything it writes there.
- `install.sh` and `kast update` fetch over HTTPS from GitHub, and each release publishes a
  `.sha256` for manual verification.

Found a vulnerability? Please report it privately via the repository's **Security** tab —
details in [SECURITY.md](SECURITY.md).

## Status & Roadmap

What is real today:

- Installer and service plumbing
- A unified GNOME Quick Settings tile — cast, receiver toggle, AirPlay sink routing, mode
- Preferences dialog (receiver name, H.265, PIN, default Wi-Fi behaviour)
- **One-click Chromecast/Miracast connect** via the `gnome-network-displays` D-Bus daemon
  (`StartStream`/`StopStream`), with a GUI fallback when the daemon isn't present
- **AirPlay video out** of a file or URL via `pyatv` (`kast airplay-cast`)
- Inbound AirPlay receive via `uxplay`
- Casting keeps Wi-Fi up by default (configurable); only the Miracast action drops it
- Video-overlay mode via native `uxplay -fs` (works on Wayland)
- In-panel Chromecast discovery via mDNS (`_googlecast._tcp`) and AirPlay discovery
  (`_airplay._tcp`), both listed in the Kast tile
- On-demand Miracast display discovery via NetworkManager's Wi-Fi P2P D-Bus interface
  (`kast miracast-targets`), listed in the panel behind a "Scan for Miracast displays" action

Known limitations:

- One-click display connect needs `gnome-network-displays` **≥ 0.99.0** (the version that
  ships the D-Bus daemon). On older versions Kast falls back to opening the GUI picker. There
  is no D-Bus `.service` activation file yet, so Kast spawns the daemon itself.
- AirPlay video out streams a **file or URL**; it is not live screen mirroring.
- Chromecast/AirPlay discovery is passive (mDNS) and refreshes on a timer; Miracast discovery
  is an active Wi-Fi P2P find that shares the radio, so it is on-demand only and never polled.

Next ideas:

- Track `gnome-network-displays` v1.0.0 (a first-party Shell extension + a user systemd
  service for the daemon); adopt the activatable service so Kast needn't spawn the daemon.

Still out of scope:

- **AirPlay live screen mirroring out.** Unlike file/URL casting, mirroring requires
  FairPlay/MFi authentication; the only Linux sender that does it (`doubletake`) works by
  running extracted Apple code and is too new/licensing-fraught to bundle in an MIT tool.
