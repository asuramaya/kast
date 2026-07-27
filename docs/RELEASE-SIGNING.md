# Release signing

Status: **armed and enforcing**, as of v0.7.4 — the family's first release to
ship able to verify itself from birth. `packaging/release-signing/allowed_signers` (and
its `install.sh`-embedded twin, `RELEASE_ALLOWED_SIGNERS`) hold the operator's
4 canonical FIDO2 pubkeys; `install.sh`'s bootstrap is fail-closed: no
`SHA256SUMS.sig`, no `ssh-keygen`, or no matching key means no install.

## Why this exists

The SHA256 check kast has always done proves a download wasn't corrupted or
truncated in transit. It proves nothing about *authenticity*: the checksum
comes from the same GitHub release it's checking, so a compromised release
asset carries its own "valid" checksum. Closing that gap needs a signature
from a key that lives outside GitHub's control entirely.

## Mechanism: SSH signatures, FIDO2 hardware key

Chosen over GPG/minisign: SSH signature verification (`ssh-keygen -Y sign` /
`-Y verify`) is already in every OpenSSH install, needs no new dependency on
either side, and — the reason for the FIDO2 requirement — supports **resident,
touch-required hardware keys** (`ecdsa-sk` / `ed25519-sk`). The private key
material never leaves the hardware token, and every signature needs a physical
touch. A compromised CI runner or build machine cannot forge a release; it
would need the physical key in hand. This is the same trust anchor the fleet's
`rotten-apple` master-identity ceremony established (2026-07-16) — kast reuses
that identity rather than minting its own (per-project keys were the
ruled-out footgun — see `~/code/REPOS/RELEASE.md`).

**The signing key must never be provisioned into CI.** That's the whole point
— CI compromise is exactly the threat this defends against. Releases are
signed by hand, from the operator's own machine, with the hardware key
attached.

## One enforcement policy, not two

Coldspot and phanspeed split their policy: a human-typed `sudo curl|bash`
bootstrap degrades to sha256-only, while their unattended daily root updater
refuses outright with no key. **kast has no unattended install path at all**
— `kast update` (whether from the tile's Update button or the CLI) is always
an explicit, human-triggered action, same as a fresh install. So kast gets
one policy for both: degrade to sha256-only with a warning while unarmed,
fail-closed once a key is provisioned — the same algorithm (sha256 manifest
check, then `ssh-keygen -Y verify` of the manifest signature against the
pinned anchor), just two implementations of it: `verify_release_tarball()`
in `install.sh` for a fresh bootstrap, and `sutra_update.py`'s `verify_dir()`
for `kast update` (see "Update-path convergence" below).

## Identity vs role — principal is WHO, namespace is WHAT-FOR

Per `~/code/REPOS/RELEASE.md` (the fleet's release doctrine): **principal**
(`-I`) is the repo's stable identity (`kast`); **namespace** (`-n`) is what a
given signature authorizes (`kast-release`). Never pass the same string for
both — that welds identity to role and only works by accident.
`allowed_signers` line format (one line per key, exactly 4 when populated):

```
kast namespaces="kast-release,pills-tag" sk-ssh-ed25519@openssh.com <b64> ra-master-<n>
```

## One-time setup — `make sync-signers`, never hand-edit

```sh
make sync-signers
```

Rebuilds `packaging/release-signing/allowed_signers` **and** `install.sh`'s embedded
`RELEASE_ALLOWED_SIGNERS` twin from ALL 4 canonical pubkeys in
`~/.ssh/asuramaya-master/*.pub` (the operator's own key home; override with
`KEY_HOME=/path/to/asuramaya-master`). Always a full rebuild, never an
append — RA's first ceremony left 3 of 4 keys unpinned that way by appending
one at a time. Refuses to run unless it finds exactly 4 canonical keys.

**Sequencing rule (do not skip):** `make sync-signers` populates the anchor.
Run it ONLY in the same act as cutting the operator's first signed kast
release — arming it any earlier bricks `kast update` against every existing
unsigned release (see "Verification semantics" below). Until then,
`packaging/release-signing/allowed_signers` ships empty and CI's `signing-sync` check
(`.github/workflows/signing-sync.yml`) just confirms that stays true.

## Per-release signing (operator, needs the FIDO2 key attached + a touch)

```sh
# Sign the checksum manifest, not each artifact — SHA256SUMS covers every
# release artifact (the tarball, and from v0.7.5 the .deb) via its checksum
# entries, so signing it transitively covers the whole release, and it's
# tiny (one line per artifact).
ssh-keygen -Y sign -f /path/to/id_asuramaya_master_N.pub -n kast-release \
  SHA256SUMS
# -> produces SHA256SUMS.sig

gh release upload vX.Y.Z SHA256SUMS.sig
```

## Verification (client side — already built)

```sh
sha256sum -c SHA256SUMS                                   # artifact matches the manifest
ssh-keygen -Y verify -f packaging/release-signing/allowed_signers \
  -I kast -n kast-release -s SHA256SUMS.sig \
  < SHA256SUMS                                             # manifest carries the operator's hand
```

Exit 0 = valid signature from the pinned principal, over exactly those
checksum bytes. Anything else is a hard failure. `install.sh`'s
`verify_release_tarball()`:

1. Checks whether `RELEASE_ALLOWED_SIGNERS` has any real key line — blank
   means no key has been provisioned yet, and verification degrades to
   sha256-only with a warning (see "One enforcement policy" above).
2. If a real key is present: requires a `SHA256SUMS.sig` asset on the
   release. Missing asset, or a signature that doesn't verify against the
   pinned principal → abort, no install.
3. Independently, the sha256 in the (now-authenticated) manifest must still
   match the downloaded tarball — the signature covers the manifest, this
   step binds the manifest to the actual bytes being installed.

## `.deb` — since v0.7.5

The tarball-only exemption is **revoked** (`~/code/REPOS/RELEASE.md`, ruling
`0d38a1f9`): the family standard is now tarball + `.deb` + one shared
`SHA256SUMS`, covering both. `make deb` builds `build/deb/kast_<ver>_all.deb`
(never installs it — see `tests/smoke.sh`); `release.yml` publishes it
alongside the tarball, one manifest, one signature.

Shape: the `.deb` installs shared, inert files under `/usr` only — binaries,
the GNOME extension source, `systemd --user` unit files (in
`/usr/lib/systemd/user/`, auto-discovered per account with no per-user copy
needed), the D-Bus session-activation file, the PipeWire RAOP config, the
desktop entry. `postinst` does nothing user-facing: no `systemctl --user`,
no `gsettings`, no `gnome-extensions enable` — those need a real user
session postinst can't reach as root, and it's also exactly how receivers
stay off by default here: by absence of code, not a guard. Per-user
activation is `kast-pill install` (mirrors coldspot's `coldspot-pill`) plus
the existing `kast install-shortcut`. See `../README.md`'s `.deb
Install` section for the user-facing walkthrough, and `packaging/deb/` for
the maintainer scripts.

`kast update` refuses to run unprivileged on a dpkg-owned install (detected
via `dpkg-query`) rather than writing a second, untracked copy of everything
— the update path for a `.deb` install is the next `.deb`, `dpkg -i`'d by
hand.

## Update-path convergence — since v0.8.0

Before v0.8.0, `kast update` re-fetched `install.sh` pinned to the release
tag and ran it — a fresh bootstrap in miniature, verified by the same shell
`verify_release_tarball()` above. That worked, but it meant a fix to the
family's shared update trust chain never reached kast: every other pill's
`<pill>-update` is a thin wrapper over the vendored `sutra_update.py` (the
family's shared update spine, `~/code/REPOS/sutra`), and kast's was a
one-off shell reimplementation instead (UNIFY.md Wave B convergence,
operator-ruled, decision `f4dc3483`).

`src/bin/kast-update` is now that thin wrapper. `kast update` (`update_run()` in
`src/bin/kast`) delegates to it instead of re-running `install.sh`. The trust
chain itself is unchanged in substance — sha256 manifest check, then
`ssh-keygen -Y verify` against the pinned anchor, degrade-while-unarmed /
fail-closed-once-armed — just executed by `sutra_update.py`'s `verify_dir()`
in Python instead of shell. That needed a real, standing `allowed_signers`
file for `kast-update` to point `-f` at (the embedded `RELEASE_ALLOWED_SIGNERS`
in `install.sh` only ever covers that one file, fetched alone over a
curl-pipe bootstrap): `install.sh` now also installs a persistent copy —
`/usr/share/kast/allowed_signers` in the `.deb`, `~/.local/share/kast/
allowed_signers` for a source install.

**`install.sh`'s own bootstrap verify is untouched, and stays untouched.**
It is the trust root that verifies the very release download that delivers
this vendored Python in the first place — on a fresh `curl | bash` there is
no `sutra_update.py` yet to delegate to. Chicken-and-egg, unconvergeable by
construction, same as every other pill's bootstrap.

kast is user-scope with no privileged component, so the one case
`sutra_update.py`'s generic engine doesn't fit — driving `install.sh` with
kast's own flags (`--skip-apt` by default, preserving already-installed
optional receivers) on a source-install update — is handled by kast's own
thin layer calling the spine's `verify_dir()`/`latest_release()` directly,
then running the verified tarball's `install.sh` itself. The `.deb` path is
unchanged: `sutra_update.py`'s own `dpkg -i` covers it exactly, refused
unprivileged with the guidance above.

`src/bin/sutra_update.py` (+ `.version`/`.commit` anchors) is vendored, never
hand-edited — `make check-sutra` is the drift guard (integrity always;
freshness as a three-way LAG/DRIFT read against the canonical checkout when
present, sutra decision `d51e090f`), wired into `make smoke` and CI. kast
vendors only `sutra_update.py` — no daemon, so `sutra.py`/`sutra_xen.py`
would be dead code (ship-what-you-import).
