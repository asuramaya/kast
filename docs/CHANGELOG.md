# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2026-07-27

Waves 4 and 5 of the REPO-STANDARD.md root-tidy pass, shipped together as one
structural release (Wave 4's v0.9.1 was never tagged before Wave 5 landed on
top of it). The operator's ruling: **the root goes superminimal, and the
README becomes a hyperlinked map of the repo**, and the two are one decision:
a minimal root is only safe when something else navigates, and a navigating
README is only worth writing once the tree has stopped trying to. It also
settles the docs-site question: **there will be no site.** GitHub renders
markdown, links between repo files work in a browser, a clone and a
terminal, and that is the whole documentation system. The sharpened root
rule throughout both waves: "would a stranger be surprised to find this
anywhere else?", not "is this file important"; almost everything fails that
test, which is why roots bloat.

Pure tree moves, no logic changes, no casting/receiving/update behavior
affected; every installed path is unchanged, only the source tree moved.
Verified with two real install-over-installed passes in each of the two
install layouts (source and `.deb`), including confirming `man-db`'s trigger
still indexes the man page at its unchanged installed path, and a full sweep
confirming every relative link across every markdown doc resolves.

### Added
- The README gains a **Map**: a six-row navigation table near the top,
  before Install, pointing at `docs/USAGE.md`, `.github/CONTRIBUTING.md`,
  `docs/ARCHITECTURE.md`, `docs/RELEASING.md`, `docs/CHANGELOG.md` and
  `.github/SECURITY.md`. The old "Where next" table at the bottom is folded
  into it rather than duplicated.

### Changed
- `bin/`, `data/`, `extension/`, `youtube-receiver/` -> `src/`. Four
  directories folded under one, since none of them are things a stranger
  needs to see as separate root entries.
- `release-signing/` -> `packaging/release-signing/`. Its repo path is only
  ever a checkout-relative fallback (`src/bin/kast-update`'s third anchor
  candidate); every installed client reads `/usr/share/kast/allowed_signers`
  or `$DATA_HOME/kast/allowed_signers` instead, so the move is zero runtime
  risk despite an earlier (mistaken) read that it was load-bearing.
- `VERSION` -> `packaging/VERSION`. `src/bin/kast` and `kast-update`'s
  checkout-relative fallbacks both updated for the new depth.
- `.shellcheckrc` -> `packaging/shellcheckrc`, no longer an auto-discovered
  dotfile, so `make check` and CI now pass `--rcfile packaging/shellcheckrc`
  explicitly.
- `CHANGELOG.md` -> `docs/CHANGELOG.md`, joining the other three topic docs.
- `man/kast.1` -> `src/data/man/man1/kast.1` (Wave 4 moved it to
  `data/man/man1/kast.1`; Wave 5's `src/` fold moved it again). A man page is
  a file installed onto the system as-is, the same class as everything else
  under `src/data/`. Also retires a self-contradiction in the family
  standard (a single-file-directory exception sitting on top of its own
  no-single-file-directories rule).
- `packages.txt` -> `packaging/packages.txt` (Wave 4). An install input
  belongs beside the other install inputs, not at root.
- `shell-extension/` -> `extension/` -> `src/extension/` (Wave 4, then
  Wave 5's fold). Kast was the only one of six family repos using the
  longer name; kast is the reference repo now, so the odd one out moved
  first. Source path only, both times: the installed path
  (`/usr/share/kast/extension/`) and the extension's UUID (`kast@asuramaya`)
  are unchanged throughout.
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` -> `.github/`.
  `.gitattributes`' export-ignore, previously a blanket rule on all of
  `.github/`, is now scoped to just `workflows/`, `ISSUE_TEMPLATE/` and
  `pull_request_template.md`, since a blanket rule would have silently
  dropped these three real, README-linked files from every release tarball:
  `git archive`'s export-ignore (like `.gitignore`) never walks into an
  already-excluded directory even for a later, more-specific un-ignore rule.

Root goes from 24 tracked entries to 12: five directories answering five
questions (`.github/`, `docs/`, `packaging/`, `src/`, `tests/`), five files a
stranger expects (`README.md`, `LICENSE`, `Makefile`, `install.sh`,
`uninstall.sh`), and git's two (`.gitignore`, `.gitattributes`).

## [0.9.0] - 2026-07-26

Adopts the family's repo structure and documentation standard
(`~/code/REPOS/REPO-STANDARD.md`, operator ruling 2026-07-26). Kast is the
reference implementation this standard was written against. No change to
any casting, receiving or update behavior; every functional path is
unchanged and re-verified.

### Added
- `docs/USAGE.md`, `docs/ARCHITECTURE.md`, `docs/RELEASING.md` — the
  family's four required topic documents (with `docs/RELEASE-SIGNING.md`,
  already present). One doc per reader: a stranger, a user, a successor
  seat, the operator at release time.
- `man/kast.1` — every verb, installed to `~/.local/share/man/man1/` for a
  source install and `/usr/share/man/man1/` for the `.deb`.
- `data/` — `applications/`, `dbus/`, `config/` and `systemd/` folded into
  one directory of files installed onto the system as-is.
- `release-signing/sync-signers.sh` (was `tools/sync-signers.sh`), beside
  the anchor it rebuilds.
- `docs/ARCHITECTURE.md`'s Standard exemptions table: kast's declared,
  on-the-record departures from the family standard (no daemon, no
  `tests/attack.sh`, `youtube-receiver/` as a second runtime).

### Changed
- `VERSION` at root is now the only version constant. `bin/kast` and
  `bin/kast-update` read it at runtime from a persistent shipped copy
  (`/usr/share/kast/VERSION` for the `.deb`, `~/.local/share/kast/VERSION`
  for a source install) instead of `bin/kast` carrying its own literal.
- `release.yml` builds release notes from the matching `CHANGELOG.md`
  section via `--notes-file`, refusing the release when it's missing,
  instead of `--generate-notes`'s commit dump.
- README trimmed to what a stranger needs before installing; the old Repo
  Layout table and Troubleshooting section moved to their real owners,
  `docs/ARCHITECTURE.md` and `docs/USAGE.md`. `SECURITY.md` expanded with
  the full threat model that was previously stranded in the README.
  `CONTRIBUTING.md` rewritten around the real `make` targets.

### Removed
- `docs/STATUS-SEAM.md`, which had claimed "design only, nothing here is
  implemented" since before the seam shipped in v0.7.3. Folded into
  `docs/ARCHITECTURE.md` in present tense, from the real implementation.
- `docs/SEAM-SPEC.md`, untracked correspondence that didn't belong in the
  repo. Moved to the seat's office.

## [0.8.0] - 2026-07-23

Converges `kast update`'s trust chain onto the family's shared update spine
(`sutra_update.py`, UNIFY.md Wave B — operator-ruled, decision f4dc3483). No
change to install.sh's own bootstrap verify, which stays exactly as it is:
it's the trust root that verifies the very download that delivers this
vendored Python on a fresh `curl | bash`, and can't converge onto itself.

### Changed
- **`kast update` / `kast-update` now run through `sutra_update.py`**
  (vendored into `bin/`, both the tarball and `.deb` layouts) instead of
  kast's own bespoke shell reimplementation. `bin/kast-update` is now a thin
  Python wrapper; `update_run()` in `bin/kast` delegates to it. The CLI
  surface is unchanged (`kast update [--check] [--json] [--apt]`, `kast
  check-update [--json]`), including the `--skip-apt`-by-default /
  feature-preserving behavior on a source-install update, and the
  Quick-Settings-tile JSON contract (`{current, latest, update_available}`)
  — kast's own layer translates the spine's `{available}` field so
  `extension.js` needed no change.
- A `.deb`-owned install refuses an unprivileged `kast update` with the same
  guidance as before (`sudo dpkg -i kast_*.deb`); `dpkg -i` needs root, and
  kast has no privileged component to run it from.

### Added
- **`bin/sutra_update.py`** vendored (+ `.version`/`.commit` integrity and
  freshness anchors) — the only sutra module kast imports; no daemon, so
  `sutra.py`/`sutra_xen.py` are deliberately not shipped (ship-what-you-import).
- **`release-signing/allowed_signers`** now shipped as a persistent runtime
  file (`/usr/share/kast/allowed_signers` in the `.deb`, `~/.local/share/kast/
  allowed_signers` for a source install) so `kast-update` has a standing
  anchor to verify against — previously this file only existed embedded in
  `install.sh` for the bootstrap, or in a checkout.
- **`make check-sutra`** — drift guard for the vendored `sutra_update.py`:
  integrity (sha256 vs `.version`) is a hard gate; freshness is the three-way
  LAG/DRIFT read (sutra decision d51e090f) against the canonical checkout
  when present. Wired into `make smoke` and CI.
- **`make check`** — canonical family grammar (`smoke attack check deb`):
  the CI lint job's static checks, runnable locally in one shot.
- **`make attack`** — a recorded exemption, not a silent gap: kast has no
  daemon or socket to fuzz.
- Two fixes already committed past v0.7.5 ride this release: `kast doctor`
  no longer crashes when the GNOME extension isn't currently registered
  (`gnome-extensions info` validly returns non-zero then), and the `.deb`
  now declares `openssh-client` (`ssh-keygen -Y verify` runs on every
  install/update now that kast is armed).

## [0.7.5] - 2026-07-19

Adds a `.deb` (the tarball-only exemption is revoked, `~/code/REPOS/RELEASE.md`
ruling `0d38a1f9`) and fixes release-tarball extraction hygiene. No behavior
change for existing tarball/checkout installs.

### Added
- **`.deb` package** (`make deb`, `packaging/deb/`) — shared, inert files
  under `/usr` only (bins, the GNOME extension source, `systemd --user` unit
  files in `/usr/lib/systemd/user/`, D-Bus/PipeWire configs, desktop entry).
  Nothing activates automatically; `postinst` touches no user session and
  no receiver, by construction. Published alongside the tarball in
  `release.yml`, covered by the same signed `SHA256SUMS`.
- **`bin/kast-pill`** — per-user pill activation for `.deb` installs
  (`install`/`remove`), mirroring coldspot's `coldspot-pill`.
- `tests/smoke.sh` builds and inspects the `.deb`'s contents (never installs
  it).

### Changed
- **Checksum manifest is now `SHA256SUMS`**, retiring the `kast.tar.gz.sha256`
  dialect — one manifest covers both the tarball and the `.deb`, matching
  the rest of the family. Signature asset is `SHA256SUMS.sig`.
- Release tarball now extracts to a named `kast/` directory
  (`--prefix=kast/`), not bare into the caller's CWD.
- `kast update` now refuses to run on a `.deb`-installed (dpkg-owned) system
  rather than writing a second, dpkg-untracked copy of everything — the
  update path for a `.deb` install is the next `.deb`, `dpkg -i`'d by hand.

## [0.7.4] - 2026-07-19

Lands the family's release-signing mechanism (`~/code/REPOS/RELEASE.md`), with
the trust anchor shipped **empty and inert** — no behavior change until the
operator's first signed release arms it. See docs/RELEASE-SIGNING.md.

### Added
- **`release-signing/allowed_signers`** — the (currently empty) SSH-signature
  trust anchor, plus a byte-identical embedded twin (`RELEASE_ALLOWED_SIGNERS`)
  in `install.sh` for the curl-pipe bootstrap, which can't read a sibling file
  over the network.
- **Two-step release verification** in `install.sh`'s `bootstrap_from_release()`
  (reached by both a fresh install and every `kast update`): sha256 against
  the published checksum manifest, then — once a key is provisioned —
  `ssh-keygen -Y verify` of that manifest's detached signature, with principal
  (`kast`) and namespace (`kast-release`) kept deliberately distinct. Degrades
  to sha256-only with a warning while unarmed; fails closed once a real key
  and a matching release exist.
- **`tools/sync-signers.sh`** / `make sync-signers` — rebuilds the anchor (and
  its embedded twin) from the operator's 4 canonical FIDO2 pubkeys
  (`~/.ssh/asuramaya-master/`), always a full rebuild, never an append.
- **`.github/workflows/signing-sync.yml`** — CI check asserting the anchor and
  its embedded copy are either both empty or both a well-formed, identical
  4-key set.
- **`tests/test_signing.sh`** — adversarial coverage of the verify path
  (tampered manifest, wrong namespace, wrong principal, untrusted key) using
  a throwaway non-hardware key; the mechanism doesn't care what backs a
  signing key, only that a valid signature exists.

### Ratified exemption
kast ships tarball-only for this pass — no `.deb` (per-user glue, not debt;
see docs/RELEASE-SIGNING.md).

## [0.7.3] - 2026-07-14

Implements the status.json seam designed in v0.7.2 (docs/STATUS-SEAM.md), plus
CLI parity bins for the family. No installed-path or default-behavior changes.

### Added
- **`$XDG_RUNTIME_DIR/kast/status.json` seam.** Every state-changing verb
  (`connect`, `disconnect`, `cast-file`, the receiver/audio/youtube
  start/stop/restart/toggle verbs) and the `status`/`targets` read verbs now
  write a snapshot (receivers, discovered devices, the active gnd session) as
  a by-product — atomic tmp+rename, dir 0700, file 0640. The Quick Settings
  tile reads it for an instant render on menu-open and watches it with a
  `Gio.FileMonitor` so CLI-driven changes appear between its 10s/20s polling
  ticks, falling back to today's shell-out whenever the file is absent (older
  CLI, first run before any verb has executed).
- **`bin/kast-healthcheck`** — kast has no daemon to ping, so the verdict is
  the seam (when one exists) agreeing with live `systemctl --user` state.
  Exit 0/1 + one line, family shape.
- **`bin/kast-update`** — CLI parity with the family; a thin delegator to the
  existing `kast update` / `kast check-update` (already tag-pinned, already
  fail-closed on a missing latest tag), not a reimplementation. Installed
  with an opt-in `kast-update.timer` (not enabled — the tile already checks
  every 6h in-process; family privacy ruling 2026-07-14 keeps updates
  click-to-install, never unattended).

## [0.7.2] - 2026-07-14

Repo-shape alignment with the family codex. Installed paths (`~/.local/bin/kast`
and friends), systemd user units, the D-Bus activation file, and the desktop
entry are byte-identical; an installed system sees no functional change.

### Changed
- **License: MIT → GPLv3.** A deliberate relicense, unifying kast with the rest
  of the asuramaya project family under GPLv3. See [LICENSE](../LICENSE).
- **Repo layout: `scripts/` is now `bin/`**, matching the family convention. Every
  reference moved with it (installer, CI, release workflow, tests, docs). The CLI
  still finds its helpers next to itself, so nothing else changes.

### Added
- **`Makefile`** in the family idiom: `make smoke` (the CLI smoke tests),
  `make pill` (per-user install of the Quick Settings extension — never root),
  and `make install` / `make uninstall` guidance wrappers around the existing
  installers (kast is user-scope; they refuse to run as root).
- **`docs/STATUS-SEAM.md`** — a design document (not yet implemented) for kast's
  status.json seam: what belongs in it, where it lives
  (`$XDG_RUNTIME_DIR/kast/status.json`), who writes it, and what the tile gains.

## [0.7.1] - 2026-07-02

### Security
Hardening pass from a full audit of every network-facing input. None of these were remotely
exploitable for code execution; they close the gaps that mattered most in the trust chain.

- **`kast update` now fetches the installer pinned to the release tag, not `main`.** Previously
  the updater piped the mutable main branch's `install.sh` to bash, so an update executed
  whatever was at the tip regardless of the release being installed. It now fetches
  `install.sh` from the `v<latest>` tag — the same tag whose tarball it then checksum-verifies —
  so an update never runs unreviewed main-branch code.
- **YouTube DIAL autoplay-on-connect is now opt-in.** DIAL has no pairing, so with autoplay on,
  any device on the LAN could start unsolicited playback the moment the receiver ran.
  Deliberate casts still play; a bare connect no longer can. Restore the old behavior with
  `KAST_YT_AUTOPLAY=1` in `uxplay.conf` on a trusted network.
- **`~/.local/state/kast` is now created 0700** (and existing 0755 dirs are tightened). It holds
  pyatv AirPlay pairing credentials, which were world-readable on shared machines.
- **`valid_ip` actually validates now**: IPv4 octets are range-checked 0–255 (`999.1.1.1` no
  longer passes) and the IPv6 form must contain a `:` (a bare hex word no longer passes).
- **`reconnect_wifi` guards its nmcli call**: the saved connection name (which can derive from
  an SSID) is passed via the unambiguous `id` selector, and a leading-`-` name is refused.

## [0.7.0] - 2026-06-19

### Added
- **Discovery now stays warm on its own.** The Quick Settings tile issues fresh mDNS queries
  periodically in the background (and immediately when you expand "Cast to…"), so the target list
  is up to date the moment you look at it — no manual Rescan needed. Cheap cached reads still drive
  the in-between renders, so opening the menu stays instant.
- **The `kast pick` / Super+K picker actively scans.** Because the picker can be launched cold from
  the app grid (with no tile keeping avahi warm), it now runs a fresh scan behind a brief
  "Looking for cast targets…" progress dialog instead of reading a possibly-empty cache.

### Backfilled
- The **v0.4.0** GitHub release's missing `kast.tar.gz` / `.sha256` assets were uploaded after the
  fact (cosmetic — v0.4.0 isn't "latest", so nothing installed from it).

## [0.6.0] - 2026-06-19

### Security
- **The installer now verifies the release tarball it downloads.** The `curl | bash` bootstrap
  fetches the published `kast.tar.gz.sha256` and checks it against the downloaded `kast.tar.gz`
  before extracting and executing, aborting on a mismatch (or if the checksum can't be fetched).
  Previously the `.sha256` was published but never used by the installer. The unreviewed
  main-branch fallback is inherently unverifiable and stays gated by its loud warning +
  `KAST_NO_UNSTABLE=1`.

### Added
- **On-demand active discovery.** `kast targets`, `cast-targets`, and `airplay-targets` accept
  `--scan` to issue fresh mDNS queries instead of reading avahi's cache, catching sinks that were
  just powered on or aren't cached yet. The Quick Settings tile's **Rescan** now does an active
  scan (with a "Scanning…" affordance) rather than just re-reading the cache; the timer-driven
  refresh stays on the fast cached read.
- **CLI smoke-test harness** (`tests/smoke.sh`), run in CI: exercises the no-hardware paths
  (help/version, discovery JSON shape, state round-trips) against a throwaway XDG home.

### Changed
- **The tile now surfaces command failures.** A failed cast/connect from the Quick Settings menu
  raises a notification with kast's own error message instead of failing silently (there's no
  terminal behind the tile). Benign user-cancels — e.g. closing the picker — exit cleanly and stay
  quiet.
- **Docs reconciled with behavior.** The README's security and roadmap sections now match reality:
  installer checksum verification is documented, and live screen mirroring out is correctly
  described as working for Chromecast/Miracast via `gnome-network-displays` (only AirPlay
  screen-mirror-out remains out of scope, FairPlay/MFi).

## [0.5.0] - 2026-06-15

### Security
- **mpv IPC socket moved out of shared `/tmp`.** The YouTube receiver's mpv control socket now lives
  in a private `0700` directory under `XDG_RUNTIME_DIR`; previously it sat in world-traversable
  `/tmp`, where any local user could connect and drive mpv (load local files, screenshot to
  arbitrary paths, read state) or exhaust memory. The IPC read buffer is now bounded too.
- **yt-dlp downloads are SHA-256 verified.** Both the install-time pre-seed and the runtime refresh
  now verify the binary against the release's published `SHA2-256SUMS` before trusting/executing it,
  and the unverified `yt-dlp -U` self-update was replaced with a verified re-download (serialized
  with `flock`, written via a random temp + atomic rename).
- **YouTube video ids are validated.** The receiver rejects anything but a `^[A-Za-z0-9_-]{11}$` id
  before building the playback URL, closing the only attacker-controlled-input-to-mpv path (the
  DIAL endpoint is unauthenticated).
- **Cast target hardening.** Chromecast device names/media beginning with `-` are refused (catt
  argument injection) and AirPlay target addresses are validated as literal IPs before use.
- **systemd receiver units hardened** with `NoNewPrivileges=yes` and a `RestrictAddressFamilies`
  allowlist.
- **Installer hardening.** The `curl | bash` bootstrap now warns loudly before falling back to the
  unreviewed `main` branch (refusable with `KAST_NO_UNSTABLE=1`), `sed` substitutions are escaped,
  and Node deps install via `npm ci` against a shipped lockfile.

### Fixed
- **Kast no longer discovers its own receiver as a cast target.** The AirPlay screen receiver
  (uxplay) advertises on the LAN, so the box was listing itself — once per network interface — in
  "Cast to…", offering to cast to itself. Discovered Chromecast/AirPlay targets resolving to any of
  this host's own IP addresses are now filtered out. Other kast boxes on the LAN are unaffected.
- **mpv is no longer orphaned on shutdown.** SIGTERM/SIGINT now kill the spawned mpv, so restarts
  don't leak an mpv process, window, and stale socket each time.
- **Prefs no longer discards hand-edited config.** Saving from the preferences dialog now patches
  the existing `uxplay.conf` in place, preserving `SHAIRPORT_ARGS`, comments, and any other manual
  lines (they were previously wiped), and stops freezing the host-qualified default name into the
  file so it stays correct after a hostname change. The `DataStore` also writes atomically, and the
  play start-offset is applied via a version-stable mpv property.

### Added
- **Settable AirPlay PIN.** Kast preferences now has a "PIN code" field under "Require PIN": leave
  it blank for uxplay's per-connection random PIN (shown on the receiving screen), or set a fixed
  4-digit code to hand out. Previously the toggle only enabled the random PIN with no way to pin or
  read it.
- **YouTube receiver no longer hides when it can't run.** When Node.js or mpv is missing the tile
  used to silently drop the YouTube switch; it now shows what's needed (e.g. "YouTube — needs
  Node.js + mpv") so the feature is discoverable. Backed by a `reason` field in `kast status --json`.

### Changed
- **Host-qualified receiver names by default.** The AirPlay screen/audio and YouTube receivers now
  advertise a host-qualified name out of the box (e.g. "Kast Receiver (hostname)") so two kast boxes
  on the same LAN are distinguishable in a sender's picker. An explicit name in the config still
  wins. (mDNS already disambiguates the service on collision; this fixes the human-facing name.)
- **Clearer fullscreen setting.** The receiver "Mode" combo (Mirror / Video overlay) is now a plain
  "Fullscreen" switch — same underlying `set-mode`, but it states what it does for the received
  screen.

## [0.4.0] - 2026-06-04

### Added
- **D-Bus activation for the display daemon.** Kast installs an activation file
  (`~/.local/share/dbus-1/services/org.gnome.NetworkDisplays.Daemon.service`) so the session bus
  starts `gnome-network-displays-daemon` on demand for one-click connect, instead of Kast spawning
  it. A runtime fallback still spawns the daemon directly when activation isn't available.
- **Self-updating yt-dlp.** The YouTube receiver now uses a user-local `yt-dlp` that Kast keeps
  current (pre-seeded at install, refreshed at most daily in the background, with `yt-dlp -U`), and
  points mpv's `ytdl_hook` at it — so YouTube changes heal without an apt upgrade. A system `yt-dlp`
  is used as a fallback when the managed copy is unavailable. `kast doctor` reports which is in use.

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
