# sutra_update — the family's update spine (UNIFY.md Wave A #1).
#
# One grammar, one trust chain, one install-path detection, three consent
# tiers. Vendored beside sutra.py into each pill's bin/; each <pill>-update
# collapses to a thin wrapper:
#
#     import sutra_update
#     sys.exit(sutra_update.main(
#         pill="byebyte", slug="asuramaya/ByeByte",
#         installed_version=read_version(),
#         anchor_candidates=["/usr/share/byebyte/allowed_signers",
#                            SRC + "/release-signing/allowed_signers"],
#         auto_enabled=cfg.get("auto_update") in ("on", True)))
#
# Tiers (UNIFY.md): --check/--json = notify tier (report only, DEFAULT);
# bare run = manual install (explicit human consent); --auto = timer path,
# honored ONLY when auto_enabled AND the anchor is armed — unattended-
# unsigned is impossible by construction. The click tier is the pill's
# packaging concern: a polkit policy that pkexec-runs the bare path.
#
# Trust chain: SHA256SUMS (or <artifact>.sha256) verified per asset with
# hashlib, then ssh-keygen -Y verify of the manifest signature against the
# pinned anchor (-I <pill> -n <pill>-release). Armed anchor => fail closed:
# no sig, no ssh-keygen, no key => no install. Empty anchor => degrade to
# hash-only WITH A LOUD WARNING (the pre-arming era only).
#
# Install paths: dpkg-owned install => fetch the release .deb, verify,
# dpkg -i (no split-brain writes over dpkg's files, ever); source install =>
# verified tarball => its own install.sh. GPLv3, stdlib-only.

SUTRA_UPDATE_VERSION = "0.1.0"

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request

API = "https://api.github.com/repos/{slug}/releases/latest"
UA = {"User-Agent": "sutra-update", "Accept": "application/vnd.github+json"}


def _vtuple(v):
    """Dotted version -> comparable tuple; non-numeric parts compare as 0."""
    parts = []
    for p in str(v).lstrip("v").split("."):
        num = "".join(ch for ch in p if ch.isdigit())
        parts.append(int(num) if num else 0)
    return tuple(parts)


def newer(latest, installed):
    return _vtuple(latest) > _vtuple(installed) and str(latest) != str(installed)


def latest_release(slug, timeout=20):
    """-> {"tag":..., "assets": {name: download_url}} or None on any failure."""
    try:
        req = urllib.request.Request(API.format(slug=slug), headers=UA)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            doc = json.load(r)
        return {"tag": doc.get("tag_name", ""),
                "assets": {a["name"]: a["browser_download_url"]
                           for a in doc.get("assets", [])}}
    except Exception:
        return None


def anchor_path(candidates):
    for p in candidates:
        if os.path.exists(p):
            return p
    return candidates[0] if candidates else None


def armed(anchor):
    """True once the anchor carries any real line — fail-closed from then on."""
    try:
        with open(anchor) as f:
            return any(l.strip() and not l.strip().startswith("#") for l in f)
    except (OSError, TypeError):
        return False


def find_manifest(names):
    return next((n for n in names
                 if n == "SHA256SUMS" or
                 (n.endswith(".sha256") and not n.endswith(".sha256.sig"))), None)


def _fetch(url, dest, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": UA["User-Agent"]})
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)


def verify_dir(workdir, manifest, sig, anchor, pill, is_armed):
    """The end-user trust chain over downloaded files. Returns (ok, reason).
    Hash check ALWAYS (every manifest-listed file present in workdir);
    signature check MANDATORY when armed, warn-and-continue only when inert."""
    mpath = os.path.join(workdir, manifest)
    try:
        with open(mpath) as f:
            entries = [l.split() for l in f if l.strip()]
    except OSError:
        return False, "manifest unreadable"
    checked = 0
    for parts in entries:
        if len(parts) != 2:
            return False, "manifest line malformed"
        want, name = parts[0], parts[1].lstrip("*")
        fpath = os.path.join(workdir, os.path.basename(name))
        if not os.path.exists(fpath):
            continue  # manifest may list assets we didn't need to download
        h = hashlib.sha256()
        with open(fpath, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        if h.hexdigest() != want:
            return False, f"sha256 mismatch: {name}"
        checked += 1
    if not checked:
        return False, "nothing verifiable was downloaded"

    if not is_armed:
        print(f"WARNING: {pill}'s signing anchor is empty — release is "
              "hash-verified ONLY (pre-arming era).", file=sys.stderr)
        return True, "hash-only (unarmed)"
    if not shutil.which("ssh-keygen"):
        return False, "armed but ssh-keygen missing (fail closed)"
    spath = os.path.join(workdir, sig) if sig else None
    if not (spath and os.path.exists(spath)):
        return False, "armed but release is unsigned (fail closed)"
    with open(mpath, "rb") as f:
        data = f.read()
    r = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", anchor,
                        "-I", pill, "-n", f"{pill}-release", "-s", spath],
                       input=data, capture_output=True)
    if r.returncode != 0:
        return False, "signature verification FAILED (fail closed)"
    return True, "hash + signature verified"


def install_mode(pill):
    """'deb' when dpkg owns this pill, else 'source'."""
    r = subprocess.run(["dpkg", "-s", pill], capture_output=True, text=True)
    return "deb" if (r.returncode == 0 and "Status: install ok installed"
                     in r.stdout) else "source"


def do_install(pill, rel, anchor, is_armed, mode):
    """Download what the mode needs + manifest + sig, verify, install.
    Returns (ok, detail)."""
    assets = rel["assets"]
    manifest = find_manifest(assets)
    if not manifest:
        return False, "release has no manifest"
    sig = manifest + ".sig" if (manifest + ".sig") in assets else None
    if mode == "deb":
        payload = next((n for n in assets if n.endswith(".deb")), None)
        if not payload:
            return False, "deb-owned install but release ships no .deb"
    else:
        payload = next((n for n in assets if n.endswith(".tar.gz")), None)
        if not payload:
            return False, "release ships no tarball"

    tmp = tempfile.mkdtemp(prefix=f"{pill}-update-")
    try:
        for name in filter(None, [payload, manifest, sig]):
            _fetch(assets[name], os.path.join(tmp, name))
        ok, reason = verify_dir(tmp, manifest, sig, anchor, pill, is_armed)
        if not ok:
            return False, reason
        print(f"verified: {reason}")
        if mode == "deb":
            r = subprocess.run(["dpkg", "-i", os.path.join(tmp, payload)])
            return (r.returncode == 0,
                    "dpkg -i " + ("ok" if r.returncode == 0 else "failed"))
        # source: extract the verified tarball, run ITS install.sh (local
        # file from verified bytes — never a network pipe).
        r = subprocess.run(["tar", "-xzf", os.path.join(tmp, payload), "-C", tmp])
        if r.returncode != 0:
            return False, "extract failed"
        inner = None
        for root, _dirs, files in os.walk(tmp):
            if "install.sh" in files and root.count(os.sep) - tmp.count(os.sep) <= 2:
                inner = os.path.join(root, "install.sh")
                break
        if not inner:
            return False, "no install.sh in verified tarball"
        r = subprocess.run(["bash", inner])
        return (r.returncode == 0,
                "install.sh " + ("ok" if r.returncode == 0 else "failed"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def notify(pill, summary, body=""):
    """UNIFY.md notification spec: best-effort toast, normal urgency,
    pointer-to-truth only."""
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", pill, "-u", "normal",
                        summary, body], capture_output=True)


def main(pill, slug, installed_version, anchor_candidates, auto_enabled=False,
         argv=None):
    argv = sys.argv[1:] if argv is None else argv
    json_out = "--json" in argv
    check_only = "--check" in argv or json_out
    auto = "--auto" in argv

    anchor = anchor_path(anchor_candidates)
    is_armed = armed(anchor)
    rel = latest_release(slug)
    latest = rel["tag"].lstrip("v") if rel else None
    avail = bool(latest) and newer(latest, installed_version)

    if json_out:
        print(json.dumps({"current": installed_version, "latest": latest,
                          "available": avail, "armed": is_armed}))
        return 0
    if rel is None:
        print("update check failed (network/API)", file=sys.stderr)
        return 1
    if not avail:
        print(f"{pill} {installed_version} is current (latest: {latest})")
        return 0

    print(f"update available: {installed_version} -> {latest}")
    if check_only:
        notify(pill, f"{pill} update available",
               f"{installed_version} → {latest} — run '{pill} update'")
        return 0
    if auto:
        if not auto_enabled:
            print("auto-update is disabled (auto_update=on to enable)")
            return 0
        if not is_armed:
            print("auto-update refused: anchor not armed — unattended "
                  "installs require the operator's signature chain",
                  file=sys.stderr)
            return 1

    mode = install_mode(pill)
    print(f"installing via {mode} path ...")
    ok, detail = do_install(pill, rel, anchor, is_armed, mode)
    print(detail if ok else f"ERROR: {detail}", file=None if ok else sys.stderr)
    if ok:
        notify(pill, f"{pill} updated", f"{installed_version} → {latest}")
    return 0 if ok else 1
