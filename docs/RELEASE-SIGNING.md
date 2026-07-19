# Release signing

Status: **mechanism built, not yet enforcing.** `release-signing/allowed_signers`
(and its `install.sh`-embedded twin, `RELEASE_ALLOWED_SIGNERS`) are currently
empty — no signing key has been provisioned. Until one is: `install.sh`'s
bootstrap degrades to sha256-only with a printed warning. The moment a real
key exists in both places and a release ships a matching
`kast.tar.gz.sha256.sig`, verification becomes mandatory and fail-closed
automatically — no further code changes needed.

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
an explicit, human-triggered action, same as a fresh install, and both funnel
through the exact same `install.sh` bootstrap. So kast gets one policy for
both: degrade to sha256-only with a warning while unarmed, fail-closed once a
key is provisioned. See `verify_release_tarball()` in `install.sh`.

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

Rebuilds `release-signing/allowed_signers` **and** `install.sh`'s embedded
`RELEASE_ALLOWED_SIGNERS` twin from ALL 4 canonical pubkeys in
`~/.ssh/asuramaya-master/*.pub` (the operator's own key home; override with
`KEY_HOME=/path/to/asuramaya-master`). Always a full rebuild, never an
append — RA's first ceremony left 3 of 4 keys unpinned that way by appending
one at a time. Refuses to run unless it finds exactly 4 canonical keys.

**Sequencing rule (do not skip):** `make sync-signers` populates the anchor.
Run it ONLY in the same act as cutting the operator's first signed kast
release — arming it any earlier bricks `kast update` against every existing
unsigned release (see "Verification semantics" below). Until then,
`release-signing/allowed_signers` ships empty and CI's `signing-sync` check
(`.github/workflows/signing-sync.yml`) just confirms that stays true.

## Per-release signing (operator, needs the FIDO2 key attached + a touch)

```sh
# Sign the checksum manifest, not the tarball itself — kast.tar.gz.sha256
# already covers kast.tar.gz via its checksum entry, so signing it
# transitively covers the whole release, and it's tiny (one line).
ssh-keygen -Y sign -f /path/to/id_asuramaya_master_N.pub -n kast-release \
  kast.tar.gz.sha256
# -> produces kast.tar.gz.sha256.sig

gh release upload vX.Y.Z kast.tar.gz.sha256.sig
```

## Verification (client side — already built)

```sh
sha256sum -c kast.tar.gz.sha256                          # artifact matches the manifest
ssh-keygen -Y verify -f release-signing/allowed_signers \
  -I kast -n kast-release -s kast.tar.gz.sha256.sig \
  < kast.tar.gz.sha256                                    # manifest carries the operator's hand
```

Exit 0 = valid signature from the pinned principal, over exactly those
checksum bytes. Anything else is a hard failure. `install.sh`'s
`verify_release_tarball()`:

1. Checks whether `RELEASE_ALLOWED_SIGNERS` has any real key line — blank
   means no key has been provisioned yet, and verification degrades to
   sha256-only with a warning (see "One enforcement policy" above).
2. If a real key is present: requires a `kast.tar.gz.sha256.sig` asset on the
   release. Missing asset, or a signature that doesn't verify against the
   pinned principal → abort, no install.
3. Independently, the sha256 in the (now-authenticated) manifest must still
   match the downloaded tarball — the signature covers the manifest, this
   step binds the manifest to the actual bytes being installed.

## Ratified exemption: tarball-only, no `.deb`

kast is per-user glue (its Makefile refuses to run as root by design, not
debt), so this signing pass covers the tarball only — a user-level `.deb` is
a possible later milestone, not a blocker here (`~/code/REPOS/RELEASE.md`,
ratified 2026-07-19).
