# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/asuramaya/kast/releases/tag/v0.1.0
