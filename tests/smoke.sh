#!/usr/bin/env bash
# Smoke tests for the kast CLI: exercise the no-hardware-needed paths and assert
# they don't crash, emit valid JSON where promised, and round-trip state. Safe to
# run anywhere — it points kast at a throwaway XDG home so it never touches real
# config/state. Discovery returns an empty set without an avahi daemon, which is
# itself the contract we check. Run: bash tests/smoke.sh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAST=(bash "${ROOT_DIR}/src/bin/kast")

# Sandbox all reads/writes into a temp XDG tree.
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}"' EXIT
export XDG_CONFIG_HOME="${TMP_HOME}/config"
export XDG_STATE_HOME="${TMP_HOME}/state"
export XDG_DATA_HOME="${TMP_HOME}/data"
export XDG_RUNTIME_DIR="${TMP_HOME}/runtime"
# TMP_HOME already exists, so -m 700 only sets this one deepest directory.
# shellcheck disable=SC2174
mkdir -p -m 700 "${XDG_RUNTIME_DIR}"

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# Assert a command succeeds (exit 0).
expect_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "${desc}"; else bad "${desc} (exit $?)"; fi
}

# Assert a command fails (non-zero) — for misuse paths.
expect_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "${desc} (expected non-zero)"; else ok "${desc}"; fi
}

# Assert stdout is valid JSON of the given jq type (array/object/...).
expect_json() {
    local desc="$1" want="$2"; shift 2
    local out
    out="$("$@" 2>/dev/null)" || { bad "${desc} (command failed)"; return; }
    if printf '%s' "${out}" | jq -e "type == \"${want}\"" >/dev/null 2>&1; then
        ok "${desc}"
    else
        bad "${desc} (not JSON ${want})"
    fi
}

# Assert stdout contains a substring.
expect_grep() {
    local desc="$1" pat="$2"; shift 2
    if "$@" 2>/dev/null | grep -q -- "${pat}"; then ok "${desc}"; else bad "${desc}"; fi
}

command -v jq >/dev/null 2>&1 || { printf 'jq is required for the smoke tests\n' >&2; exit 1; }

printf 'kast smoke tests\n'

# --- basic surface ---
expect_ok    "version"                       "${KAST[@]}" version
expect_grep  "version matches VERSION file"  "$(tr -d '[:space:]' < "${ROOT_DIR}/packaging/VERSION")" "${KAST[@]}" version
expect_grep  "--help lists airplay-cast"      "airplay-cast" "${KAST[@]}" --help
expect_grep  "--help documents --scan"        "--scan" "${KAST[@]}" --help
expect_grep  "--help documents update --check" "update \[--check" "${KAST[@]}" --help
expect_fail  "unknown subcommand errors"      "${KAST[@]}" definitely-not-a-command

# --- discovery emits valid JSON (empty without an avahi daemon, still an array) ---
expect_json  "cast-targets --json"     array "${KAST[@]}" cast-targets --json
expect_json  "airplay-targets --json"  array "${KAST[@]}" airplay-targets --json
expect_json  "targets --json"          array "${KAST[@]}" targets --json
expect_json  "cast-targets --scan"     array "${KAST[@]}" cast-targets --scan --json
expect_json  "targets --scan --json"   array "${KAST[@]}" targets --scan --json
expect_json  "status --json is object" object "${KAST[@]}" status --json

# --- status.json seam (docs/STATUS-SEAM.md): status is a listed by-product verb ---
# THIS SANDBOX'S OWN ISOLATION MAKES SYSTEMD --USER UNREACHABLE HERE, always,
# confirmed directly (not assumed): `systemctl --user is-active` fails to
# connect once XDG_RUNTIME_DIR (overridden above, for this file's own
# isolation) no longer points at the socket systemd actually created, and
# that holds regardless of DBUS_SESSION_BUS_ADDRESS. Before the honesty fix,
# that unreachability silently collapsed to a confident "inactive" and a
# written seam -- this assertion passed for years on a lie it never noticed,
# because "inactive" was also what a correct read would have said. Verified
# live against the actual pre-fix code before trusting this replacement: it
# reports {"active": false} with no distinguishing field at all, and it
# writes the seam anyway, under this exact sandboxed environment.
out="$("${KAST[@]}" status --json)"
if echo "${out}" | jq -e '.receiver.active_unknown == true and .receiver.active == false' >/dev/null 2>&1; then
    ok "status: systemd-unreachable state reports unknown honestly (active_unknown), not a fabricated inactive"
else
    bad "status --json didn't report active_unknown under an unreachable systemd bus: ${out}"
fi
SEAM_FILE="${XDG_RUNTIME_DIR}/kast/status.json"
if [[ ! -f "${SEAM_FILE}" ]]; then
    ok "status.json seam: correctly skipped writing rather than fabricate a snapshot (systemd unreachable in this sandbox)"
elif jq -e '
        .version == 1 and (.written_at | type) == "number"
        and (.receivers.airplay_screen | IN("active","inactive","unknown"))
        and (.receivers.airplay_audio  | IN("active","inactive","unknown"))
        and (.receivers.youtube        | IN("active","inactive","unknown"))
        and (.devices | type) == "array"
        and (.session == null or .session.active == true)
    ' "${SEAM_FILE}" >/dev/null 2>&1
then
    ok "status.json seam has the documented shape"
else
    bad "status.json seam has the documented shape"
fi

# --- state round-trips (no hardware) ---
expect_grep  "get-mode defaults to mirror"   "mirror" "${KAST[@]}" get-mode
"${KAST[@]}" set-mode video-overlay >/dev/null 2>&1
expect_grep  "set-mode persists"             "video-overlay" "${KAST[@]}" get-mode
"${KAST[@]}" set-mode mirror >/dev/null 2>&1
expect_fail  "set-mode rejects bad mode"     "${KAST[@]}" set-mode bogus

# --- make deb: builds a real .deb; contents include the shared/inert files.
# Builds and inspects only — never installed (that's a human's `dpkg -i`).
if command -v dpkg-deb >/dev/null 2>&1; then
    if make -C "${ROOT_DIR}" deb >/tmp/kast-deb-build.log 2>&1; then
        DEBFILE="${ROOT_DIR}/build/deb/kast_$(tr -d '[:space:]' < "${ROOT_DIR}/packaging/VERSION")_all.deb"
        if [[ -f "${DEBFILE}" ]]; then
            CONTENTS="$(dpkg-deb --contents "${DEBFILE}")"
            deb_ok=1
            for want in usr/bin/kast usr/bin/kast-pill usr/bin/kast-healthcheck usr/bin/kast-update \
                        usr/share/kast/lib/sutra_update.py usr/share/kast/lib/sutra_update.version \
                        usr/share/kast/allowed_signers \
                        usr/lib/systemd/user/uxplay.service usr/lib/systemd/user/kast-update.timer \
                        usr/share/kast/extension/kast@asuramaya/extension.js \
                        usr/share/applications/kast-center.desktop \
                        usr/share/man/man1/kast.1 \
                        usr/share/pipewire/pipewire.conf.d/50-raop.conf; do
                grep -q "${want}" <<<"${CONTENTS}" || { bad "deb missing ${want}"; deb_ok=0; }
            done
            [[ "${deb_ok}" -eq 1 ]] && ok "deb built and contents verified (never installed)"

            # --- family dependency standard (operator ruling 2cd900ce):
            # apt installs Recommends by default, so a Depends/Recommends
            # split doesn't actually stop an unwanted package arriving --
            # only Suggests does. Assert the real field names and contents
            # dpkg-deb reports, not just that the Makefile has the right
            # `echo` lines: a rename typo (e.g. "Recommend:") would pass
            # every check above and still auto-pull GNOME Shell onto a
            # headless box. ---
            deb_depends="$(dpkg-deb -f "${DEBFILE}" Depends)"
            deb_suggests="$(dpkg-deb -f "${DEBFILE}" Suggests)"
            deb_recommends="$(dpkg-deb -f "${DEBFILE}" Recommends)"
            dep_ok=1
            for want in python3 jq systemd openssh-client; do
                grep -q "${want}" <<<"${deb_depends}" || { bad "deb Depends missing ${want}"; dep_ok=0; }
            done
            for want in avahi-daemon avahi-utils gnome-network-displays \
                        network-manager pipewire-audio pipewire-pulse uxplay \
                        wireplumber wpasupplicant zenity; do
                grep -q "${want}" <<<"${deb_suggests}" || { bad "deb Suggests missing ${want}"; dep_ok=0; }
            done
            # gnome-shell is deliberately NOT in Suggests: it has no packages.txt
            # line (that file's optional tier gets apt-get installed unconditionally
            # by install.sh, so a gnome-shell entry there would pull a full desktop
            # onto every source install), and Suggests is meant to be generated from
            # exactly that file with no exceptions (Tantra, ruling 2cd900ce). It's
            # prose in the Description instead -- assert it stays there, not silently
            # dropped from both.
            deb_description="$(dpkg-deb -f "${DEBFILE}" Description)"
            grep -qi "gnome-shell" <<<"${deb_suggests}" && { bad "deb Suggests has gnome-shell (should be prose-only, ruling 2cd900ce)"; dep_ok=0; }
            grep -qi "GNOME Shell" <<<"${deb_description}" || { bad "deb Description lost its gnome-shell note"; dep_ok=0; }
            [[ -z "${deb_recommends}" ]] || { bad "deb still has a Recommends field (apt installs it by default): ${deb_recommends}"; dep_ok=0; }
            [[ "${dep_ok}" -eq 1 ]] && ok "deb Depends is the hard floor, everything else is Suggests (not Recommends)"
        else
            bad "make deb produced no .deb"
        fi
    else
        bad "make deb failed"; cat /tmp/kast-deb-build.log >&2
    fi
else
    printf '  skip deb build (dpkg-deb not found)\n'
fi

# --- source install layout (install.sh) also ships the vendored update spine
# + signing anchor — the exact bug Werner/tjmax each hit independently: a
# pill that vendors sutra_update.py but ships it in only ONE install layout
# crashes on import only on a real user's machine, never in whichever layout
# CI happens to build. ---
src_ok=1
# Single-quoted on purpose: these are the literal install.sh source strings
# to grep for, not variables to expand here.
# shellcheck disable=SC2016
for want in '${DATA_HOME}/${APP_ID}/lib/sutra_update.py' '${DATA_HOME}/${APP_ID}/lib/sutra_update.version' '${DATA_HOME}/${APP_ID}/allowed_signers' '${DATA_HOME}/${APP_ID}/VERSION' '${DATA_HOME}/man/man1/kast.1'; do
    grep -qF "${want}" "${ROOT_DIR}/install.sh" || { bad "install.sh missing ${want}"; src_ok=0; }
done
[[ "${src_ok}" -eq 1 ]] && ok "install.sh ships sutra_update.py + allowed_signers + VERSION + man page (source layout)"

# --- the bootstrap preamble must resolve to the REAL vendored copy, not just
# fail to crash. A staging mistake (e.g. vendoring to src/data/lib instead of
# src/share/kast/lib, three other seats' independent mistake per Alfred msg
# 2572) can still pass every check above: kast-update never crashes, install.sh
# still names the right strings — the only thing that catches it is asking
# where the import actually resolved. First-class check, not an inferred side
# effect of the binary not crashing (alfred, msg 2572, citing ramstein
# b211651).
if resolve_out="$(ROOT_DIR="${ROOT_DIR}" python3 - <<'PY' 2>&1
import importlib.util
import os
from importlib.machinery import SourceFileLoader

root = os.environ["ROOT_DIR"]
# src/bin/kast-update has no .py suffix, so spec_from_file_location can't
# infer a loader on its own; hand it one explicitly. Its own sutra bootstrap
# preamble (BOOTSTRAP.md) runs as part of exec_module below and finds
# src/share/kast/lib/sutra_update.py on its own; no sys.path setup needed
# here. Everything below kast-update's `if __name__ == "__main__":` guard
# does NOT run, since the loader gives this module a different __name__.
loader = SourceFileLoader("kast_update_smoke", os.path.join(root, "src/bin/kast-update"))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

expected = os.path.realpath(os.path.join(root, "src/share/kast/lib/sutra_update.py"))
actual = os.path.realpath(mod.sutra_update.__file__)
if actual != expected:
    raise SystemExit(
        f"sutra bootstrap resolved to {actual}, expected {expected} "
        "(BOOTSTRAP.md's fixed path arithmetic, not wherever it happened to find one)")
print(actual)
PY
)"; then
    ok "kast-update's sutra bootstrap resolves to the real vendored copy (${resolve_out})"
else
    bad "kast-update's sutra bootstrap did not resolve to the expected path: ${resolve_out}"
fi

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
