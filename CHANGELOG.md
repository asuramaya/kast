# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-05-29

### Changed
- **`kast update` is now feature-aware.** It detects the optional receivers you have installed
  (shairport-sync / the YouTube receiver) and preserves them across the update, and adds
  `kast update --apt` to also refresh system packages (the default stays sudo-free so the tile's
  one-click update keeps working).
- Documentation: README rewritten for the 0.3.x glue-layer surface (receivers, control center,
  Chromecast file-cast, tiered install, the redesigned tile, GNOME 49–50).

## [0.3.0] - 2026-05-29

Kast becomes a glue layer across casting protocols, not just a launcher.

### Added
- **AirPlay video out** (Apple TV / AirPlay-2 TVs) via pyatv: `kast airplay-targets`,
  `kast airplay-cast <target> <url-or-file>` (URL or local file), `kast airplay-pick <target>`
  (graphical file chooser), and `kast airplay-pair <target> [--gui]` for receivers that require
  a code (`--gui` prompts for the PIN with a zenity dialog).
- **One-click display connect.** With `gnome-network-displays` ≥ 0.99.0 (which ships a D-Bus
  daemon), `kast connect <name>` / `kast display-connect <name>` connect straight to a
  Chromecast or Miracast sink via `StartStream`, and `kast disconnect` stops it — no GUI
  detour. Falls back to the picker when the daemon is absent or still discovering.
- **Live cast state.** `kast status --json` reports `outbound.cast` (active/target/unit) by
  tracking the transient stream unit; the tile shows "Casting · <target>" and offers Disconnect
  only while a stream is live.
- **Control center** (`kast control`): a backend-agnostic device control layer. Capabilities
  are discovered per device, never assumed — an AirPlay-only TV exposes ~stop+volume, an Apple
  TV the full remote (transport, nav, power, now-playing, apps). `kast control` lists
  controllable devices with their capabilities; `kast control <target> <action>` runs a
  normalized action (stop/play/pause/next/previous/seek/volume_up/volume_down/set_volume/
  power_on/power_off/key/launch_app); `kast control <target> now-playing` reports playback.
  Unsupported actions are refused with a clear message rather than a silent no-op. A
  gnd screen-mirror session is controllable only as stop (= disconnect).
- **Control Center window** (`kast control-center [target]`): a GTK4/Adwaita remote that
  renders only the controls a device supports — now-playing, transport, a volume slider, a
  d-pad, and power, each shown per the device's reported capabilities. The Kast tile gains a
  **Control** section with quick controls (stop / play-pause / volume / power) per controllable
  device and a **Control Center…** link to the full window.
- **AirPlay audio receiver** (`shairport-sync`): the box can now receive AirPlay *audio*
  (lossless, with metadata) in addition to uxplay's screen mirroring. New `audio-receiver-*`
  commands and an "AirPlay Receiver (audio)" toggle in the tile; off by default like the screen
  receiver. The packaged build is AirPlay audio (classic) — AirPlay-2 multi-room needs nqptp,
  which Ubuntu does not package.
- **YouTube receiver**: a small Node app (`yt-cast-receiver`) lets phone YouTube / YT-Music apps
  cast to the box over DIAL — no Google Cast auth needed — and plays the stream with `mpv`.
  New `youtube-receiver-*` commands and a "YouTube Receiver" tile toggle; off by default. Needs
  Node + mpv + yt-dlp (expect occasional yt-dlp updates as YouTube changes).
- The receiver matrix is now explicit: Miracast sink and Chromecast-receive are intentionally
  **not** included (the only Linux Miracast sink is unreliable; Google Cast receive requires a
  device key/cert a third party cannot obtain) — see the README Scope.
- **Chromecast file-cast parity** (`catt`): `kast cast-file <target> <url-or-file>` plays a file
  or URL on a Chromecast (mirroring the AirPlay file-cast), and `kast connect <chromecast> <media>`
  casts the file while `kast connect <chromecast>` still mirrors the screen. The tile gains a
  "cast file…" action per Chromecast (alongside "mirror screen"). Uses `catt` (pipx-isolated).
- **Miracast in the picker.** `kast pick` now offers "Scan for Miracast displays…" and lists
  found sinks for one-click connect (`kast pick --miracast` scans directly), so the graphical
  picker covers all three display protocols, not just Chromecast/AirPlay.
- **`kast repair`** reinstalls the pipx helpers (pyatv/catt) when a Python/OS upgrade breaks
  their venvs; AirPlay commands also self-heal a broken pyatv venv automatically before failing.
- **Tiered dependencies.** The core install stays lean (casting out, AirPlay screen receive, the
  picker, and pipx-isolated pyatv + catt for AirPlay-out / Chromecast file-cast / control center).
  Heavier receivers are opt-in: `./install.sh --with-airplay-audio` (shairport-sync),
  `--with-youtube` (nodejs/npm/mpv/yt-dlp), or `--with-all`. Each feature degrades gracefully and
  `kast doctor` names the missing piece.
- **Unified cast surface:** `kast targets [--json]` lists every discovered target (Chromecast +
  AirPlay) tagged with its capabilities, and `kast connect` routes each to the right backend.
- The Kast tile now lists AirPlay receivers (each with **cast file…** and **pair…** actions)
  and connects to Chromecast/Miracast in one click.

### Changed
- **Tile menu redesigned for usability.** Instead of one long flat list, the menu is now lean
  with progressive disclosure: a contextual "Casting · X" + Disconnect (only while streaming),
  two collapsible groups — **Cast to…** (discovered Chromecast/AirPlay/Miracast targets) and
  **Receive** (the screen/audio/YouTube on/off switches) — plus **Control Center…** and **Kast
  Settings…**. All configuration (receiver names, mirror mode, H.265, PIN, Wi-Fi behaviour) moved
  into the preferences dialog; audio-output routing is left to GNOME's native Sound menu. Clicking
  the tile opens the graphical picker.
- Clicking a discovered Chromecast/Miracast in the tile now **connects** instead of opening
  the GUI picker.
- **`kast pick` is kast's own graphical "cast to…" menu** (a zenity list of discovered
  Chromecast/AirPlay targets, a Disconnect entry when streaming, and a hand-off to the GUI
  picker for Miracast). The app launcher and the `Super+K` shortcut now open it instead of
  launching `gnome-network-displays` directly. It works regardless of GNOME shell version, so
  it keeps working even when a shell upgrade temporarily disables the Quick Settings tile.
- The Quick Settings extension now supports **GNOME Shell 50** (Ubuntu 26.04) as well as 49.

### Fixed
- The desktop launcher ran `gnome-network-displays` directly (its menu, not kast's); it now
  runs `kast pick`. `kast doctor` flags the tile as out of date when the running GNOME is
  newer than the extension's `shell-version`, and confirms the `kast pick` picker is available.
- AirPlay is driven through the pyatv **library** (a small `kast-airplay` helper) instead of
  pyatv's `atvremote`/`atvscript` console scripts, which crash on Python 3.14 (the removed
  `asyncio.get_event_loop()` fallback). `kast doctor` now flags a pyatv venv broken by a
  Python upgrade and points at `pipx reinstall pyatv`.
- mDNS device names now decode avahi's `\DDD` escapes (so `Samsung Q70 Series (75)` and
  accented names render correctly) while still refusing to decode control bytes — a hostile
  name cannot inject ESC/newline/tab.

## [0.2.0] - 2026-05-21

### Added
- **Preferences dialog** (`prefs.js`, opens from the Extensions app and a "Kast Settings…"
  menu entry): receiver name, H.265, require-PIN, and a default "drop Wi-Fi when casting"
  toggle — all written to `~/.config/kast/uxplay.conf` (the CLI's existing config).
- `KAST_DROP_WIFI_DEFAULT` config option, honored by `kast open-display-cast`.
- `kast open-display` (opens the GNOME Display settings panel); "Sound/Display Settings…"
  links in the tile menu.

### Changed
- **The Cast and Receiver tiles are now one unified "Kast" tile.** Its menu has a Cast
  section (Display Cast / Miracast / Chromecast + Miracast discovery) and a Receiver section
  (an on/off switch, mode, AirPlay output), plus the settings links and version/update —
  fixing the two tiles landing in different Quick Settings rows.
- **The AirPlay receiver is now OFF by default.** It's a LAN-facing listener, so `install.sh`
  no longer enables/starts it — turn it on from the Kast tile (or `kast receiver-start`) when
  you want to receive. When on it is **PIN-gated** (`UXPLAY_ARGS=(-pin)`); the PIN is a 4-digit
  speed bump, not strong auth, so the real protection is leaving the receiver off when idle.

### Security
- `prefs.js` sanitizes values written to the bash-sourced `uxplay.conf` (strips `$ \` " \`
  and newlines from the receiver name, rejects non-token args), so GUI input can't inject
  shell commands that would run when the CLI sources the config.
- `kast cast-targets` strips tab/CR/LF from attacker-controlled mDNS device names so a
  malicious advert can't forge or corrupt entries in the cast list. (Verified against a live
  hostile advert: no field-shift, no address spoof, no exec — avahi pre-escapes control
  chars and the name only ever reaches `jq` as a string.)
- `install.sh` passes `--` to `apt-get install` so a crafted `packages.txt` line cannot be
  parsed as an apt option.

### Fixed
- The installer reliably **enables** the extension on a fresh install by writing
  `org.gnome.shell enabled-extensions` directly (`gnome-extensions enable` refuses an
  extension the running shell hasn't scanned yet). `uninstall.sh` removes the uuid.

## [0.1.3] - 2026-05-21

### Changed
- **The UI is now native GNOME Quick Settings tiles.** The shell extension was rebuilt on
  the GNOME 49 QuickSettings API into a **Cast** tile (display picker + Chromecast/Miracast
  discovery) and a **Receiver** toggle (on/off pill + mode + AirPlay output + version/update),
  appearing in the system menu next to Wi-Fi/Bluetooth.
- `install.sh` now installs and enables the extension (and removes the old tray). Log out and
  back in to load it — Wayland can't hot-reload shell extensions.

### Removed
- The AppIndicator tray (`scripts/kast-tray.py`, `kast-tray.service`) and its dependencies
  (`python3-gi`, `gir1.2-ayatanaappindicator3-0.1`, `gir1.2-gtk-3.0`), replaced by the
  Quick Settings extension.

## [0.1.2] - 2026-05-21

### Added
- `kast check-update` and `kast update` — compare against the latest GitHub release and
  update in place (`update` re-runs the installer for the newest release).
- `kast status --json` now includes the running `version`.
- Tray: receiver-mode **radio items** (the active mode is checked), an "⬆ Update to vX.Y.Z"
  entry when an update is available, and a footer showing the installed version.
- Shell extension brought to tray parity: version + current mode in the status line, an
  update notice + action, receiver-mode toggle, and a "Rescan Chromecast Targets" action.

### Changed
- Tray and extension present the receiver mode as a single selectable control instead of
  two separate "set mode" actions; the redundant "Toggle Receiver" item was removed from
  the extension.

## [0.1.1] - 2026-05-21

### Added
- Community health files: `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue
  forms, and a pull-request template.
- README: "Tray menu" and "Troubleshooting" sections.

### Fixed
- The post-install "Remove" hint now works for `curl | bash` installs (it pointed at a
  local `./uninstall.sh` that those users don't have).
- The `curl | bash` bootstrap no longer leaks its temporary download directory in `/tmp`.

## [0.1.0] - 2026-05-21

Initial release. A Win+K-style cast panel for GNOME on Ubuntu 25.10.

### Added
- One-line `install.sh` that self-bootstraps when piped from `curl` (downloads the
  latest release tarball), plus a symmetric `uninstall.sh`.
- `kast` CLI: `status`, `sinks`, `cast-targets` (Chromecast via mDNS), `miracast-targets`
  (Wi-Fi Display via NetworkManager Wi-Fi P2P), `open-display-cast [--drop-wifi]`,
  AirPlay sink routing, receiver control, `set-mode`/`get-mode`, `doctor`, `version`.
- AppIndicator tray (`kast-tray`) and a GNOME Shell extension, both listing discovered
  Chromecast targets and offering an on-demand Miracast scan.
- Inbound AirPlay receiver via `uxplay`; video-overlay mode via native `uxplay -fs`
  (works on Wayland).
- GitHub Actions: `ci` (ShellCheck, Python, JS, JSON, CLI smoke) and `release`
  (tag-triggered tarball + checksum + GitHub Release).

### Notes
- `gnome-network-displays` exposes no connect API, so kast discovers and lists cast
  targets but hands off to its picker to complete the connection.

[0.3.1]: https://github.com/asuramaya/kast/releases/tag/v0.3.1
[0.3.0]: https://github.com/asuramaya/kast/releases/tag/v0.3.0
[0.2.0]: https://github.com/asuramaya/kast/releases/tag/v0.2.0
[0.1.3]: https://github.com/asuramaya/kast/releases/tag/v0.1.3
[0.1.2]: https://github.com/asuramaya/kast/releases/tag/v0.1.2
[0.1.1]: https://github.com/asuramaya/kast/releases/tag/v0.1.1
[0.1.0]: https://github.com/asuramaya/kast/releases/tag/v0.1.0
