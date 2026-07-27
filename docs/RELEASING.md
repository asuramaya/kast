# Releasing kast

How a version becomes a signed release. The trust chain itself is described in
[RELEASE-SIGNING.md](RELEASE-SIGNING.md); this is the running order.

Two people are involved and only one of them can finish it. A maintainer prepares and tags.
The operator signs, by hand, with a physical key. No automation can stand in for that step,
and the signing key never goes near CI.

## 1. Prepare

Bump `packaging/VERSION`. It's the one version constant (`src/bin/kast` and `kast-update` both
read it at runtime); CI asserts it matches the tag.

Write the `docs/CHANGELOG.md` entry under a `## [X.Y.Z] - YYYY-MM-DD` heading. This is not
optional bookkeeping: the release workflow lifts that section verbatim as the release notes,
and refuses to publish when the section is missing. Whatever you write there is what the
world reads.

Run the checks:

```bash
make check          # shellcheck, node --check, the CLI's own self-test
make check-sutra    # the vendored spine matches canonical, byte for byte
make smoke          # end to end, against a throwaway XDG home
```

`check-sutra` failing on freshness means the shared spine moved and Kast hasn't caught up.
Re-vendor before releasing rather than after.

## 2. Arm, tag and publish in one sitting

Arming means putting the operator's public keys into `packaging/release-signing/allowed_signers`. Once
that file has a real line in it, verification becomes mandatory forever, for every client that
installed from that release onward. That property is the whole point, and it's also the trap:

> **An armed anchor with no signature is a broken update path.** A client whose installed copy
> is armed will refuse a release that has no `.sig`, and it is right to. So arming, tagging,
> publishing and signing belong to one sitting, with the operator present. Never arm and walk
> away.

kast has been armed since v0.7.4 and every release since has been signed, so for kast this
means: don't tag unless the operator is available to sign shortly after.

```bash
make sync-signers     # rebuild the anchor from the canonical public keys
git tag vX.Y.Z && git push origin vX.Y.Z
```

`sync-signers` rebuilds the anchor from all four canonical keys. It never appends, so a key
that has been retired upstream disappears here too.

CI then builds `kast.tar.gz`, `kast_X.Y.Z_all.deb` and a `SHA256SUMS` manifest covering both,
and publishes them with the notes it lifted from the CHANGELOG. It signs nothing. That's
deliberate: if CI could sign, then anyone who compromised the workflow or the account could
sign whatever they pushed, and the anchor would be protecting nothing.

## 3. The operator seals it

The operator verifies the published bytes, signs the manifest offline with the FIDO2 key, and
uploads the detached signature:

```bash
gh release upload vX.Y.Z SHA256SUMS.sig --clobber
```

One signature over the manifest covers every artifact in the release, because the manifest
covers them all. In practice this runs through the family's seal desk, which derives its queue
from published releases and shows anything published without a `.sig` as awaiting the seal.

## Rules that don't bend

* **A sealed release is never re-cut.** If something is wrong with it, the fix is the next
  version. Re-cutting breaks every copy that already verified it.
* **The signing key never enters CI**, in any form, for any reason.
* **Arming commits are scoped** to the anchor files alone. Not `git add -A`. A stray one has
  put session files into a public commit before, and the history had to be rewritten by hand.
* **`--notes-file`, never `--generate-notes`.** A commit dump is not release notes.

## When it goes wrong

**CI refuses with "no docs/CHANGELOG.md section"** means the heading doesn't contain the version.
Add the section and re-push the tag.

**The tag assertion fails** means `packaging/VERSION` and the tag disagree. Fix it, delete the tag, tag
again.

**A client reports "armed but release is unsigned"** means the release was published and never
sealed. Nothing is broken in the artifact; it needs the operator's signature uploading.
