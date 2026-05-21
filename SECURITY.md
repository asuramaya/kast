# Security Policy

## Supported versions

kast is pre-1.0; only the latest release receives fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, use GitHub's
private vulnerability reporting:

- Go to the repo's **Security** tab → **Report a vulnerability**.

You'll get an acknowledgement, and a fix or mitigation will be coordinated before any
public disclosure.

## Scope notes

kast runs entirely in your user session — there is no privileged daemon. It does:

- route PipeWire audio sinks and launch desktop apps,
- read/modify NetworkManager Wi-Fi state and run a Wi-Fi P2P find (for Miracast),
- set a GNOME custom keybinding,
- run `uxplay` as an **inbound AirPlay receiver**, which listens on the local network.

If you don't want the receiver reachable, stop it (`kast receiver-stop`) or require a PIN
via `UXPLAY_ARGS=(-pin)` in `~/.config/kast/uxplay.conf`. The apt packages in
`packages.txt` are upstream-maintained; report issues in them to their respective projects.
