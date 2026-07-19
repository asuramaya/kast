#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# `make sync-signers` — rebuild release-signing/allowed_signers AND
# install.sh's embedded RELEASE_ALLOWED_SIGNERS twin from the fleet's
# canonical pubkeys, per ~/code/REPOS/RELEASE.md's sync-signers doctrine.
#
# Canonical key home (operator ruling 13ee52ce): ~/.ssh/asuramaya-master/ —
# OUTSIDE every repo, never committed, never a sibling checkout. This is a
# LOCAL-ONLY act by construction: CI can never reach $HOME, so CI's
# signing-sync check asserts internal consistency only (well-formed anchor +
# embedded copy matches), never canonical equality.
#
# ALWAYS a full rebuild, never an append: RA's first ceremony left 3 of 4
# keys unpinned across other repos by appending one key at a time. Refuses to
# run unless it finds exactly 4 canonical keys, so a partial/broken key home
# can't silently produce a partial anchor.
#
# SEQUENCING: this populates the anchor. Per RELEASE.md, run it ONLY in the
# same act as cutting the operator's first signed kast release — arming
# release-signing/allowed_signers any earlier bricks kast-update against
# every existing unsigned release.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
PRINCIPAL="kast"
NAMESPACES="kast-release,pills-tag"

KEY_HOME="${KEY_HOME:-$HOME/.ssh/asuramaya-master}"
if [[ ! -d "$KEY_HOME" ]]; then
  echo "ERROR: canonical key home not found at $KEY_HOME." >&2
  echo "       Set KEY_HOME=/path/to/asuramaya-master and retry." >&2
  exit 1
fi

mapfile -t pubs < <(find "$KEY_HOME" -maxdepth 1 -name '*.pub' | LC_ALL=C sort)
if [[ "${#pubs[@]}" -ne 4 ]]; then
  echo "ERROR: expected exactly 4 canonical pubkeys in $KEY_HOME, found ${#pubs[@]}." >&2
  echo "       Never partially sync — see RELEASE.md's sync-signers section." >&2
  exit 1
fi

anchor="$HERE/release-signing/allowed_signers"
tmp="$(mktemp)"
for p in "${pubs[@]}"; do
  printf '%s namespaces="%s" %s\n' "$PRINCIPAL" "$NAMESPACES" "$(cat "$p")"
done > "$tmp"
mv "$tmp" "$anchor"
echo "rebuilt $anchor from ${#pubs[@]} canonical keys ($KEY_HOME)"

# install.sh's curl-pipe-bash bootstrap fetches only itself over the network,
# so it can't read the sibling allowed_signers file at that point — the same
# content is embedded directly, BYTE-FOR-BYTE (CI's drift check compares them
# exactly, per RELEASE.md — "a failed build, not a warning"). Read the anchor
# file straight from disk in Python rather than round-tripping it through a
# bash "$(...)" capture, which silently strips its trailing newline.
# RELEASE_ALLOWED_SIGNERS is single-quoted (install.sh) so this can span
# multiple lines with no escaping.
python3 - "$HERE/install.sh" "$anchor" <<'PYEOF'
import re
import sys

install_path, anchor_path = sys.argv[1], sys.argv[2]
content = open(anchor_path).read()
src = open(install_path).read()
if "'" in content:
    sys.exit("ERROR: canonical key content contains a literal single quote — "
              "can't safely embed it in install.sh's single-quoted constant.")
new, n = re.subn(r"RELEASE_ALLOWED_SIGNERS='.*?'",
                  lambda _: f"RELEASE_ALLOWED_SIGNERS='{content}'",
                  src, count=1, flags=re.DOTALL)
if n != 1:
    sys.exit("ERROR: RELEASE_ALLOWED_SIGNERS='...' not found in install.sh")
open(install_path, 'w').write(new)
PYEOF
echo "synced install.sh's embedded RELEASE_ALLOWED_SIGNERS"
