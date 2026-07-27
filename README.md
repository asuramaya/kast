# Kast

[![ci](https://github.com/asuramaya/kast/actions/workflows/ci.yml/badge.svg)](https://github.com/asuramaya/kast/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/asuramaya/kast?sort=semver)](https://github.com/asuramaya/kast/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Kast puts a Windows-style `Win+K` cast panel into GNOME, as a native Quick Settings tile.
Open the system menu, pick a target, cast. You can control what you're casting to, and
receive casts back onto this machine.

Linux has no single upstream stack for AirPlay, Miracast and Chromecast, so Kast is glue.
It wires together the packages Ubuntu already ships, plus two pipx-isolated helpers, and
puts them behind one tile, one shortcut, and one CLI.

Requires Ubuntu 25.10 or 26.04, GNOME Shell 49 or 50, on Wayland.

## What works

|  | Cast out, this machine to a device | Receive in, a device to this machine |
|---|---|---|
| **AirPlay** | audio via PipeWire RAOP, and video from a file or URL via `pyatv` | screen mirroring via `uxplay` (PIN-gated), audio via `shairport-sync` |
| **Chromecast** | screen mirroring, and media from a file or URL via `catt` | not possible <sup>1</sup> |
| **Miracast** | display, one click, via `gnome-network-displays` | not included <sup>2</sup> |
| **YouTube / YT-Music** | | over DIAL via `yt-cast-receiver` and `mpv`, with no Google account |

Every inbound receiver ships off. They're LAN-facing listeners, so turn one on while you're
receiving and off when you're done.

One thing Kast can't do: AirPlay live screen mirroring *out*. That needs FairPlay/MFi
authentication, and the only Linux sender runs extracted Apple code.

<sup>1</sup> Google Cast requires a device key and a Google-signed certificate that a third
party cannot obtain. <sup>2</sup> MiracleCast is the only Linux implementation. It's
unreliable, and it wants the Wi-Fi radio to itself.

## Map

| | |
|---|---|
| Use it | [docs/USAGE.md](docs/USAGE.md), or `man kast` |
| Change it | [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) |
| Understand how it's built | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Cut a release | [docs/RELEASING.md](docs/RELEASING.md) |
| See what changed | [docs/CHANGELOG.md](docs/CHANGELOG.md) |
| Report a vulnerability | [.github/SECURITY.md](.github/SECURITY.md) |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/asuramaya/kast/main/install.sh | bash
```

Or from a clone: `git clone https://github.com/asuramaya/kast && cd kast && ./install.sh`.

The core install stays lean. The heavier inbound receivers are opt-in:

```bash
./install.sh --with-airplay-audio   # shairport-sync, for AirPlay audio receive
./install.sh --with-youtube         # nodejs, mpv and yt-dlp, for YouTube receive
./install.sh --with-all             # everything
```

Other flags: `--skip-apt`, `--no-shortcut`, `--shortcut '<Primary>k'`.

There's also a `.deb` on the [latest release](https://github.com/asuramaya/kast/releases/latest).
Install it with `sudo dpkg -i kast_*.deb`, then once per account, as yourself, run
`kast-pill install`. The `.deb` puts only inert shared files under `/usr`. Nothing activates
on its own, and nothing needs root again. The two install paths are independent, so don't mix
them on one machine.

## First run

Log out and back in. Wayland can't hot-reload shell extensions, so the Kast tile appears in
Quick Settings only at your next login. Then:

```bash
kast doctor     # checks the whole stack, with a fix hint for anything broken
```

The Kast tile now sits beside Wi-Fi and Bluetooth in the system menu, and `Super+K` opens the
picker from anywhere.

## Everyday use

```
kast pick                       the graphical picker, same as Super+K
kast targets --scan             everything discoverable right now
kast connect <name>             mirror this screen to it
kast cast-file <name> <url>     play a file or URL on it
kast control-center             the remote for the connected device
kast status                     what's casting, what's receiving
kast doctor                     what's wrong, and how to fix it
```

Every command, plus the tile, the preferences dialog and troubleshooting, lives in
[docs/USAGE.md](docs/USAGE.md) and `man kast`.

## Updating

```bash
kast update            # update in place from the latest release
kast update --check    # just say whether one is available
```

Before it installs anything, `kast update` verifies the release against its published
`SHA256SUMS` manifest and that manifest's SSH signature. It's the same trust chain as a fresh
install, written up in [docs/RELEASE-SIGNING.md](docs/RELEASE-SIGNING.md). Optional features
you already have survive the update, and apt is left alone unless you pass `--apt`. A `.deb`
install updates with the next `.deb` instead.

## Uninstall

```bash
./uninstall.sh            # remove kast, keep your config
./uninstall.sh --purge    # also remove ~/.config/kast and state
```

Apt packages stay, since they're shared system components. The isolated helpers come off with
`pipx uninstall pyatv` and `pipx uninstall catt`.

## Security

Kast runs entirely in your user session. There is no privileged daemon.

* The inbound receivers are off by default, and they listen on the LAN. The AirPlay screen
  receiver is PIN-gated, but four digits is a speed bump rather than authentication. Off when
  idle is the real control.
* `install.sh` and `kast update` fetch over HTTPS, and both verify checksum and signature
  before installing.
* Discovered device names are attacker-controlled, and they only ever get handled as text.

The full threat model, and how to report a vulnerability privately, is in
[.github/SECURITY.md](.github/SECURITY.md).

Kast belongs to a family of small GNOME utilities that share a runtime backbone, an update
spine and a signed-release chain. GPLv3.
