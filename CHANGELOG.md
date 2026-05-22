# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/asuramaya/kast/releases/tag/v0.2.0
[0.1.3]: https://github.com/asuramaya/kast/releases/tag/v0.1.3
[0.1.2]: https://github.com/asuramaya/kast/releases/tag/v0.1.2
[0.1.1]: https://github.com/asuramaya/kast/releases/tag/v0.1.1
[0.1.0]: https://github.com/asuramaya/kast/releases/tag/v0.1.0
