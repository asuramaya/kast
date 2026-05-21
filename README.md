# Kast

[![ci](https://github.com/asuramaya/kast/actions/workflows/ci.yml/badge.svg)](https://github.com/asuramaya/kast/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/asuramaya/kast?sort=semver)](https://github.com/asuramaya/kast/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`Kast` is a one-line Ubuntu setup that brings a **Windows `Win+K`-style cast panel** to
GNOME on Ubuntu 25.10. Press the shortcut, pick a target, cast — and route audio to AirPlay
speakers from the top bar.

It is not a single protocol-unified backend. Linux has no one upstream stack for AirPlay,
Miracast, and Chromecast, so Kast wires together the native packages that already ship in
Ubuntu 25.10 and presents them behind one tray menu and one shortcut.

Why "Kast" and not "Ctrl+K": the Windows feature is **`Win+K`** (Cast / Connect), so the
default shortcut here is `Super+K` — `Super` is the Windows key. The name keeps the `K`.

- Outbound AirPlay audio via PipeWire RAOP
- Outbound Miracast and Chromecast display casting via `gnome-network-displays`
- Inbound AirPlay receiver mode via `uxplay`
- Ubuntu top-bar tray controls for receiver state, AirPlay sink selection, and fast launch
  into display casting

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
5. Installs a top-bar tray controller and autostarts it at login.
6. Adds a GNOME app launcher and a default `Super+K` shortcut.

## Uninstall

```bash
./uninstall.sh            # remove kast (keeps your config)
./uninstall.sh --purge    # also remove ~/.config/kast and state
```

Apt packages are left installed (they are shared system components).

## Repo Layout

- [install.sh](install.sh): bootstrap entrypoint (self-bootstraps when piped from curl)
- [uninstall.sh](uninstall.sh): symmetric uninstaller (`--purge` also removes config/state)
- [scripts/kast](scripts/kast): runtime CLI used by services and the shell extension
- [scripts/kast-tray.py](scripts/kast-tray.py): AppIndicator controller shown next to the Wi-Fi icon
- [shell-extension/kast@asuramaya/](shell-extension/kast@asuramaya): optional native GNOME Shell panel UI
- [systemd/user/uxplay.service](systemd/user/uxplay.service): AirPlay receiver (uses `uxplay -fs` for video-overlay mode)

## Default UX

- Top bar tray item next to network controls
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

## Tray menu

The top-bar tray (and the optional shell extension) show, top to bottom:

- Receiver state and mode (mirror / video-overlay)
- **Display Cast…** (keeps Wi-Fi) and **Display Cast — Miracast (drops Wi-Fi)…**
- **Chromecast Targets** discovered on the LAN, with a rescan action
- **Miracast Displays**, behind an on-demand **Scan for Miracast displays**
- AirPlay output sinks (click to route audio there) and **Use Local Speakers**
- Receiver controls (start/stop/restart) and mode toggles

Selecting a discovered target opens `gnome-network-displays` to complete the connection
(see the limitation below).

## Troubleshooting

Run `kast doctor` first — it checks tools, discovery, the receiver, outbound casting, audio
routing, and desktop integration, and prints a fix hint for each problem.

- **`kast: command not found`** — `~/.local/bin` isn't on your `PATH`. Add it to your shell
  profile, or log out and back in.
- **No tray icon** — the tray relies on AppIndicator support. On GNOME, enable the
  *AppIndicator and KStatusNotifierItem Support* extension, then
  `systemctl --user restart kast-tray.service`.
- **No Miracast displays found** — discovery is an on-demand Wi-Fi P2P find; some adapters
  can't do P2P at all (`kast doctor` reports this). Try again near the display.
- **Chromecast cast drops the network** — fixed in the default action; only the explicit
  *Miracast (drops Wi-Fi)* item disconnects Wi-Fi. Use **Display Cast…** for Chromecast.
- **AirPlay sinks don't appear** — confirm the RAOP config is installed (`kast doctor`) and
  the speaker is on the same network.

## Status & Roadmap

What is real today:

- Installer and service plumbing
- Top-bar tray controller (receiver state, AirPlay sink routing, mode toggle)
- Inbound AirPlay receive via `uxplay`
- Casting keeps Wi-Fi up by default; only the explicit Miracast action drops it
- Video-overlay mode via native `uxplay -fs` (works on Wayland)
- In-panel Chromecast discovery via mDNS (`_googlecast._tcp`), listed in the tray and the
  shell extension
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
