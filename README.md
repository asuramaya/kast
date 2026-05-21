# Kast

[![ci](https://github.com/asuramaya/kast/actions/workflows/ci.yml/badge.svg)](https://github.com/asuramaya/kast/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/asuramaya/kast?sort=semver)](https://github.com/asuramaya/kast/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`Kast` is a one-line Ubuntu setup that brings a **Windows `Win+K`-style cast panel** to
GNOME on Ubuntu 25.10 — as native **Quick Settings tiles**. Open the system menu, pick a
target, cast — and route audio to AirPlay speakers, all from the same panel as Wi-Fi/BT.

It is not a single protocol-unified backend. Linux has no one upstream stack for AirPlay,
Miracast, and Chromecast, so Kast wires together the native packages that already ship in
Ubuntu 25.10 and presents them behind two Quick Settings tiles and one shortcut.

- Outbound AirPlay audio via PipeWire RAOP
- Outbound Miracast and Chromecast display casting via `gnome-network-displays`
- Inbound AirPlay receiver mode via `uxplay`
- A **Cast** tile and a **Receiver** toggle in GNOME Quick Settings for targets, receiver
  state, AirPlay sink selection, and mirror/overlay mode

## Scope

- `AirPlay audio out`: yes
- `AirPlay display out`: no native sender backend included
- `Miracast display out`: yes, through `gnome-network-displays`
- `Chromecast display out`: yes, through `gnome-network-displays`
- `AirPlay receive in`: yes, through `uxplay`

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
3. Installs the `kast` CLI into `~/.local/bin`.
4. Installs `uxplay` user services.
5. Installs and enables the GNOME Quick Settings extension (Cast + Receiver tiles).
6. Adds a GNOME app launcher and a default `Super+K` shortcut.

> **Log out and back in** after installing — Wayland can't hot-reload shell extensions,
> so the Kast tiles appear in Quick Settings only on your next login.

## Updating

```bash
kast check-update    # is a newer release available?
kast update          # update in place from the latest GitHub release
```

The Quick Settings tiles also check periodically and surface an "⬆ Update to vX.Y.Z"
entry when one is available — clicking it runs the update for you.

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
- [shell-extension/kast@asuramaya/](shell-extension/kast@asuramaya): the GNOME Quick Settings UI (Cast + Receiver tiles)
- [systemd/user/uxplay.service](systemd/user/uxplay.service): AirPlay receiver (uses `uxplay -fs` for video-overlay mode)

## Default UX

- Cast + Receiver tiles in the GNOME Quick Settings menu (top-right), next to Wi-Fi/BT
- `Super+K` (the `Win+K` equivalent) launches display casting
- `kast status` shows stack status; `kast doctor` runs a full health check
- `kast cast-targets` lists Chromecast / Google Cast devices discovered on the LAN (mDNS)
- `kast miracast-targets` scans for Wi-Fi Display (Miracast) sinks on demand
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

## Quick Settings tiles

Open the system menu (top-right). Two Kast tiles sit alongside Wi-Fi/Bluetooth:

- **Cast** — click the tile to open the display picker; the ⌄ expands a native menu with
  **Display Cast…**, **Miracast (drops Wi-Fi)…**, discovered **Chromecast** targets (+ rescan),
  and an on-demand **Scan for Miracast displays**.
- **Receiver** — the pill toggles the inbound AirPlay receiver on/off; the ⌄ expands
  mirror/overlay **Mode**, **AirPlay output** sinks (+ Use Local Speakers), **Restart**,
  **Sound Settings…**, and the version / update entry.

Selecting a discovered target opens `gnome-network-displays` to complete the connection
(see the limitation below).

## Troubleshooting

Run `kast doctor` first — it checks tools, discovery, the receiver, outbound casting, audio
routing, and desktop integration, and prints a fix hint for each problem.

- **`kast: command not found`** — `~/.local/bin` isn't on your `PATH`. Add it to your shell
  profile, or log out and back in.
- **No Kast tiles in Quick Settings** — the extension loads only after a fresh login on
  Wayland. Log out/in, then check `gnome-extensions list --enabled | grep kast` and
  `kast doctor`. Enable manually with `gnome-extensions enable kast@asuramaya`.
- **No Miracast displays found** — discovery is an on-demand Wi-Fi P2P find; some adapters
  can't do P2P at all (`kast doctor` reports this). Try again near the display.
- **Chromecast cast drops the network** — fixed in the default action; only the explicit
  *Miracast (drops Wi-Fi)* item disconnects Wi-Fi. Use **Display Cast…** for Chromecast.
- **AirPlay sinks don't appear** — confirm the RAOP config is installed (`kast doctor`) and
  the speaker is on the same network.

## Status & Roadmap

What is real today:

- Installer and service plumbing
- GNOME Quick Settings tiles (Cast + Receiver) — receiver toggle, AirPlay sink routing, mode
- Inbound AirPlay receive via `uxplay`
- Casting keeps Wi-Fi up by default; only the explicit Miracast action drops it
- Video-overlay mode via native `uxplay -fs` (works on Wayland)
- In-panel Chromecast discovery via mDNS (`_googlecast._tcp`), listed in the Cast tile
- On-demand Miracast display discovery via NetworkManager's Wi-Fi P2P D-Bus interface
  (`kast miracast-targets`), listed in the panel behind a "Scan for Miracast displays" action

Known limitations:

- Selecting a discovered target opens `gnome-network-displays` to finish the connection:
  it owns the screencast pipeline and exposes no CLI/D-Bus to connect to a specific sink,
  so Kast can discover and list devices but not auto-connect to them.
- Chromecast discovery is passive (mDNS) and refreshes on a timer; Miracast discovery is an
  active Wi-Fi P2P find that shares the radio, so it is on-demand only and never auto-polled.

Next ideas:

- If a future `gnome-network-displays` exposes a connect API (or a headless sink backend
  lands), wire the listed targets straight through to a one-click connect.

Still out of scope:

- AirPlay display sender support — no Linux-native sender backend exists to wrap
