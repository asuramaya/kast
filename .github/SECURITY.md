# Security Policy

## Supported versions

kast is pre-1.0. Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's private
vulnerability reporting instead: go to the repo's **Security** tab, then **Report a
vulnerability**.

You'll get an acknowledgement, and a fix or mitigation will be coordinated before any public
disclosure.

## What Kast is, from a security point of view

Kast runs entirely in your user session. There is no privileged daemon, no setuid binary, and
nothing that needs root after installation. What it does have is a set of properties worth
understanding, because most of them were chosen deliberately and a few of them are honest
limitations rather than defences.

**The inbound receivers are off by default, and they listen on the LAN.** `uxplay`,
`shairport-sync` and the YouTube DIAL receiver all accept connections from the network when
running. They ship disabled, and the tile's switches are the intended way to turn one on for
as long as you're using it. Off when idle is the real control here, not any of the settings
below.

**The AirPlay screen receiver's PIN is a speed bump, not authentication.** With `-pin` set,
a sender must enter a 4-digit code shown on screen. Four digits is weak, and the PIN does
nothing to protect `uxplay`'s parser from a malicious sender that gets past it. Treat it as
friction against the wrong person in the same room, and nothing more.

**Discovered device names are attacker-controlled.** Anything on your network can advertise
whatever name it likes over mDNS. Those names only ever reach `jq` and UI labels as text.
Avahi's escape sequences get decoded and control bytes get refused.

**`~/.config/kast/uxplay.conf` is sourced like a shell rc file.** That's how it can carry
arbitrary `uxplay` flags, and it means the file is code running as you. The preferences dialog
escapes everything it writes there. If you edit it by hand, treat it as a script you own.

**Installs and updates verify before they install.** `install.sh` and `kast update` fetch over
HTTPS, check the download against the release's published `SHA256SUMS` manifest, and verify
that manifest's SSH signature against the anchor pinned inside the client. A mismatch aborts.
Downloaded `yt-dlp` copies are SHA-256 verified too.

**CI cannot sign a release.** The signing key is FIDO2 hardware in the maintainer's hand and
never enters GitHub Actions in any form. This is why releases are published unsigned and
signed afterwards by hand: if the workflow could sign, then compromising the workflow or the
account would be enough to sign anything. See
[docs/RELEASE-SIGNING.md](../docs/RELEASE-SIGNING.md).

**The trust anchor is fail-closed once armed.** As soon as
`packaging/release-signing/allowed_signers` holds a real key, signature verification is mandatory
forever for every client installed from that release onward. There is no flag to turn it off.

**There is one unverifiable path, and it warns.** `install.sh` can fall back to installing
from the `main` branch, which by definition has no release manifest to check against. It says
so loudly, and `KAST_NO_UNSTABLE=1` refuses it outright.

**The `.deb` installs inert files.** It writes shared components under `/usr` and activates
nothing. Turning Kast on for an account is a separate, unprivileged `kast-pill install`.

**The pipx helpers are isolated per tool.** `pyatv` and `catt` live in their own virtual
environments rather than in your system or user site-packages.

## Out of scope

The apt packages in `packaging/packages.txt` are upstream-maintained. Please report issues in `uxplay`,
`shairport-sync`, `gnome-network-displays`, `pyatv` or `catt` to those projects; we'll help
route a report if you're unsure where it belongs.
