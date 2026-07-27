# How Kast is built

For anyone picking up the code, including a future maintainer who wasn't here when it was
written. If you want to *use* Kast, [USAGE.md](USAGE.md) is the document you want.

## The shape of the thing

Kast has no daemon. Every sibling in this family runs one, and that daemon owns the truth
about its domain; Kast is the exception, because its truth doesn't belong to it. What's
discoverable lives in avahi's cache. What's running lives in `systemctl --user`. What's
casting lives inside `gnome-network-displays`. Kast queries those, arranges the answers, and
gets out of the way.

That makes the CLI the centre of gravity. `src/bin/kast` is bash, it's the source of truth for
behaviour, and everything else calls it:

```
GNOME tile ──shells out──▶  kast <verb> --json  ──▶  avahi / systemctl / gnd / pyatv / catt
    │                              │
    └──reads──▶ status.json ◀──writes as a by-product──┘
```

The extension never talks to a device. It renders what the CLI tells it. That boundary is
deliberate: it means the whole product is testable from a terminal, and a broken tile can't
take casting down with it.

## The status.json seam

The tile used to re-derive everything on a timer, which meant a fan-out of bash, avahi-browse,
jq and systemctl subprocesses every ten seconds, and a blocking one at the exact moment you
opened the menu. So state-changing verbs now leave a snapshot behind them.

`$XDG_RUNTIME_DIR/kast/status.json`, mode 0640, written to a temp file and moved into place so
a reader never sees a half-written document:

```json
{ "version": 1, "written_at": 1770000000,
  "receivers": { "airplay_screen": "active", "airplay_audio": "inactive",
                 "youtube": "inactive", "checked_at": 1770000000 },
  "devices": [ { "name": "Living Room TV", "kind": "airplay",
                 "addr": "10.0.0.5", "discovered_at": 1770000000 } ],
  "session": { "active": true, "target": "Living Room TV",
               "via": "gnd", "since": 1769999900 } }
```

Three rules hold it together.

**Writing it must stay cheap.** It happens as a by-product of ordinary verbs, so it reads the
avahi cache and never triggers a scan. If a write would cost real time, it doesn't belong in
the snapshot.

**The document ages as a whole.** Every device carries `discovered_at`, but the honest
staleness signal is `written_at` on the document. A reader judging freshness from that needs no
per-device bookkeeping, and Kast keeps none.

**The seam is an optimisation, never a dependency.** `jq` missing, no runtime dir, a failed
write: each of those returns quietly and leaves no file. The extension watches the path with a
`Gio.FileMonitor` and falls back to shelling out when it isn't there. Nothing breaks when the
snapshot is absent; the menu just goes back to being slow.

## Where everything lives

`src/` is the one row that groups four directories rather than naming one thing: `bin/`,
`data/`, `extension/` and `youtube-receiver/` all live under it, so this map matters more than
it used to, since the root listing no longer shows them individually.

| Path | What it is |
|---|---|
| `src/bin/kast` | the CLI, in bash. The source of truth, and the integration point for everything else |
| `src/bin/kast-airplay` | Python helper driving `pyatv`, for AirPlay video out and device control |
| `src/bin/kast-control-center` | the GTK4/Adwaita remote window |
| `src/bin/kast-pill` | per-user activation for `.deb` installs, `install` and `remove` |
| `src/bin/kast-update` | the engine behind `kast update`, a thin wrapper over the vendored spine |
| `src/bin/kast-healthcheck` | CLI parity with the family: does the status.json seam agree with live systemd reality. Not wired into any timer; kast has no daemon to check periodically |
| `src/bin/sutra_update.py` | the family's shared update spine, vendored byte-identical from `sutra` |
| `src/bin/sutra_update.version`, `.commit` | drift anchors for the vendored copy |
| `src/extension/kast@asuramaya/` | the GNOME pill: `extension.js` is the tile, `prefs.js` the settings dialog |
| `src/data/` | files installed onto the system as-is: `systemd/user/` (the three off-by-default receiver units, plus the update service and timer), `config/` (the PipeWire RAOP drop-in, the `uxplay.conf` example), `applications/` (the desktop entry that opens the picker), `dbus/` (the activation file that starts the gnome-network-displays daemon on demand), `man/man1/kast.1` (the man page: every verb, kept in sync with `docs/USAGE.md` by hand, same as every sibling pill's) |
| `src/youtube-receiver/` | a separate Node runtime, the DIAL receiver built on `yt-cast-receiver` |
| `packaging/deb/` | `.deb` maintainer scripts. `make deb` builds one and never installs it |
| `packaging/packages.txt` | the apt packages the installer needs, one per line with comments |
| `packaging/release-signing/allowed_signers` | the trust anchor for release verification |
| `packaging/release-signing/sync-signers.sh` | rebuilds that anchor from the canonical public keys |
| `packaging/VERSION` | the one version constant (REPO-STANDARD.md); `src/bin/kast` and `kast-update` read it at runtime |
| `packaging/shellcheckrc` | shellcheck's rule exceptions; passed explicitly via `--rcfile` since it's no longer an auto-discovered dotfile |
| `docs/CHANGELOG.md` | what changed, and when |
| `tests/` | `smoke.sh` and `test_signing.sh` |
| `install.sh`, `uninstall.sh` | the user-scope installer and its symmetric removal |

`src/youtube-receiver/` is the one piece written in another language, and it's here because the
only maintained DIAL receiver for YouTube is a Node library. It runs as its own user service,
speaks to `mpv`, and touches nothing else in the tree. Its `node_modules` are installed on the
target machine rather than committed.

## The two install layouts

Kast installs one of two ways, and the code has to work under both.

The **tarball or checkout** path is user-scope. `install.sh` puts executables in
`~/.local/bin`, units in `~/.config/systemd/user`, and the extension in
`~/.local/share/gnome-shell/extensions`. Nothing needs root, and `kast update` can replace it
in place.

The **`.deb`** path installs shared, inert files under `/usr` and activates nothing. A user
then runs `kast-pill install` once per account to copy the pill into their home and enable it.
Removing the package cleans `/usr` but leaves those per-account copies, which is why
`kast-pill remove` exists.

The two must not be mixed on one machine, and `kast update` refuses to run the tarball
installer over a `.deb` install rather than making a mess of it.

Both layouts have to ship the full vendored set from `src/bin/`. Shipping the executables while
forgetting `sutra_update.py` produces an install that works until the first update and then
dies on an import, which is a mistake this family has made more than once.

`packaging/VERSION` ships the same way, as a persistent runtime file next to the install
(`/usr/share/kast/VERSION` for the `.deb`, `~/.local/share/kast/VERSION` for a source
install), so `src/bin/kast` and `kast-update` can read it after the fact rather than carry their
own copy of the number.

## The update path

`kast update` runs `src/bin/kast-update`, which is a thin wrapper over `src/bin/sutra_update.py`. That
file is vendored byte-identical from the `sutra` repo, and `make check-sutra` proves it:
integrity is a hard failure, while freshness is three-way. A vendored commit that matches
canonical HEAD is fine, an ancestor of HEAD is lag and warns, and anything not in canonical's
history is drift and fails.

The crypto is entirely the spine's. What stays local to Kast is the install orchestration,
because `kast update` has to preserve the optional features you already have and honour
`--skip-apt`. The rule the family settled on: convergence means the *crypto* is shared, while
the install driver may stay pill-local when it has real flags to honour.

`install.sh` keeps its own shell verification for the bootstrap download, and always will.
That's the trust root that delivers the vendored Python in the first place, so it can't be
written in the thing it delivers.

Details of the trust chain are in [RELEASE-SIGNING.md](RELEASE-SIGNING.md), and the release
process is in [RELEASING.md](RELEASING.md).

## Conventions worth knowing before you edit

* Bash runs under `set -euo pipefail` and stays ShellCheck-clean. Intentional exceptions live
  in `packaging/shellcheckrc`, not in inline comments.
* New runtime dependencies stay out unless Ubuntu already ships them. The pipx-isolated
  helpers are the exception, and they're isolated for exactly that reason.
* The CLI is the integration point. If the tile needs something, the CLI grows a `--json`
  verb; the tile does not grow logic.
* Device names arrive from the network and are attacker-controlled. They reach `jq` and labels
  as text only. Avahi escapes get decoded, control bytes get refused.
* `~/.config/kast/uxplay.conf` is sourced like a shell rc file. Anything writing to it escapes
  what it writes.

## Standard exemptions

Kast's declared departures from the family repo standard. Anything the standard asks for and
Kast doesn't have is listed here. A gap that isn't in this table is a bug, not a choice.

| Item | Why |
|---|---|
| no daemon, and no vendored `sutra.py` | Kast is the family's glue layer. It has no daemon, so the shared `ControlServer` runtime doesn't apply. It vendors `sutra_update.py` alone, which is standalone and stdlib-only |
| no `tests/attack.sh` | there's no daemon and no socket surface of its own to fuzz. The inbound receivers are upstream programs, and hardening them belongs upstream. `make attack` exists and says so rather than being silently absent |
| `src/youtube-receiver/` as a second runtime | the only maintained DIAL receiver for YouTube is a Node library. Documented above, and confined to its own directory |
