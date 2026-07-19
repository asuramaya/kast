#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Unit test for install.sh's release-signing verification (docs/RELEASE-SIGNING.md,
# ~/code/REPOS/RELEASE.md). Generates a throwaway (non-hardware) ed25519 key to
# prove the ssh-keygen -Y sign/verify roundtrip itself is wired correctly —
# verification doesn't care what backed the real signing key, only that a
# valid signature exists, so this is a faithful test of the mechanism the
# real FIDO2 key will use. Skips (not fails) if ssh-keygen is unavailable.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ssh-keygen not found — skipping signing tests"
  exit 0
fi

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- the shipped anchor is either the empty placeholder OR a well-formed,
# armed 4-key set — never partial, never malformed. Mirrors the shape check
# in .github/workflows/signing-sync.yml; this can't confirm the keys are the
# operator's actual canonical set (CI can't reach ~/.ssh/asuramaya-master),
# only that the anchor's shape is sane either way.
armed=0
anchor_content="$(cat "$HERE/release-signing/allowed_signers" 2>/dev/null || true)"
if [[ -n "${anchor_content//[[:space:]]/}" ]]; then
  armed=1
  anchor_lines="$(grep -c . "$HERE/release-signing/allowed_signers")"
  [[ "$anchor_lines" -eq 4 ]] \
    || fail "release-signing/allowed_signers is armed but has ${anchor_lines} lines, expected exactly 4"
  echo "shipped allowed_signers is armed with 4 keys OK"
else
  echo "shipped allowed_signers is the empty placeholder OK"
fi

# --- load install.sh's verify functions without running an install ----------
KAST_INSTALL_SOURCED=1 source "$HERE/install.sh"

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# --- has_signing_key() -------------------------------------------------------
: > "$td/empty"
has_signing_key "$td/empty" && fail "empty file must not count as a provisioned key"

printf '\n\n   \n' > "$td/blank"
has_signing_key "$td/blank" && fail "whitespace-only file must not count as a provisioned key"

has_signing_key "$td/does-not-exist" && fail "a missing file must not count as a provisioned key"

# no-arg form reads the global RELEASE_ALLOWED_SIGNERS — must agree with
# whichever shape the anchor actually shipped in (checked above): armed
# means a real key IS provisioned, unarmed means it isn't.
if [[ "$armed" -eq 1 ]]; then
  has_signing_key || fail "an armed RELEASE_ALLOWED_SIGNERS must count as a provisioned key"
else
  has_signing_key && fail "empty RELEASE_ALLOWED_SIGNERS must not count as a provisioned key"
fi
echo "has_signing_key() OK"

# --- verify_signature(): real roundtrip -------------------------------------
# principal = WHO (kast's identity, "kast"); namespace = WHAT-FOR
# ("kast-release") — deliberately distinct, per RELEASE.md's identity-vs-role
# split (conflating the two was the bug alfred's review caught on siblings).
PRINCIPAL="kast"
NS="kast-release"
keyfile="$td/id_test"
ssh-keygen -t ed25519 -N "" -C test -f "$keyfile" >/dev/null 2>&1

signers="$td/allowed_signers"
printf '%s namespaces="%s,pills-tag" %s\n' "$PRINCIPAL" "$NS" "$(cat "$keyfile.pub")" > "$signers"

data="$td/data"
printf 'the exact bytes a checksum manifest would contain\n' > "$data"
ssh-keygen -Y sign -f "$keyfile.pub" -n "$NS" "$data" >/dev/null 2>&1
sig="$data.sig"

verify_signature "$data" "$sig" "$signers" "$PRINCIPAL" "$NS" \
  || fail "a valid signature from the pinned key must verify"
echo "verify_signature(): valid signature accepted OK"

# tampered data must fail
tampered="$td/tampered"
printf 'the exact bytes a checksum manifest would contain\nEXTRA\n' > "$tampered"
verify_signature "$tampered" "$sig" "$signers" "$PRINCIPAL" "$NS" \
  && fail "a signature over different bytes must not verify"
echo "verify_signature(): tampered data rejected OK"

# signature from a DIFFERENT (untrusted) key must fail against this allowed_signers
otherkey="$td/id_other"
ssh-keygen -t ed25519 -N "" -C other -f "$otherkey" >/dev/null 2>&1
otherdata="$td/data2"
printf 'the exact bytes a checksum manifest would contain\n' > "$otherdata"
ssh-keygen -Y sign -f "$otherkey.pub" -n "$NS" "$otherdata" >/dev/null 2>&1
othersig="$otherdata.sig"
verify_signature "$data" "$othersig" "$signers" "$PRINCIPAL" "$NS" \
  && fail "a signature from an untrusted key must not verify"
echo "verify_signature(): untrusted key rejected OK"

# wrong namespace must fail (binds the signature to its intended use)
verify_signature "$data" "$sig" "$signers" "$PRINCIPAL" "some-other-namespace" \
  && fail "a namespace mismatch must not verify"
echo "verify_signature(): namespace mismatch rejected OK"

# wrong principal must fail (identity, not just role, is pinned)
verify_signature "$data" "$sig" "$signers" "not-kast" "$NS" \
  && fail "a principal mismatch must not verify"
echo "verify_signature(): principal mismatch rejected OK"

echo "release-signing verification OK"
