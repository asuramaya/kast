#!/usr/bin/env bash
# Smoke tests for the kast CLI: exercise the no-hardware-needed paths and assert
# they don't crash, emit valid JSON where promised, and round-trip state. Safe to
# run anywhere — it points kast at a throwaway XDG home so it never touches real
# config/state. Discovery returns an empty set without an avahi daemon, which is
# itself the contract we check. Run: bash tests/smoke.sh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAST=(bash "${ROOT_DIR}/bin/kast")

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
expect_grep  "version matches VERSION file"  "$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")" "${KAST[@]}" version
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
SEAM_FILE="${XDG_RUNTIME_DIR}/kast/status.json"
if [[ -f "${SEAM_FILE}" ]] && jq -e '
        .version == 1 and (.written_at | type) == "number"
        and (.receivers.airplay_screen | IN("active","inactive"))
        and (.receivers.airplay_audio  | IN("active","inactive"))
        and (.receivers.youtube        | IN("active","inactive"))
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
        DEBFILE="${ROOT_DIR}/build/deb/kast_$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")_all.deb"
        if [[ -f "${DEBFILE}" ]]; then
            CONTENTS="$(dpkg-deb --contents "${DEBFILE}")"
            deb_ok=1
            for want in usr/bin/kast usr/bin/kast-pill usr/bin/kast-healthcheck usr/bin/kast-update \
                        usr/bin/sutra_update.py usr/bin/sutra_update.version \
                        usr/share/kast/allowed_signers \
                        usr/lib/systemd/user/uxplay.service usr/lib/systemd/user/kast-update.timer \
                        usr/share/kast/extension/kast@asuramaya/extension.js \
                        usr/share/applications/kast-center.desktop \
                        usr/share/pipewire/pipewire.conf.d/50-raop.conf; do
                grep -q "${want}" <<<"${CONTENTS}" || { bad "deb missing ${want}"; deb_ok=0; }
            done
            [[ "${deb_ok}" -eq 1 ]] && ok "deb built and contents verified (never installed)"
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
for want in '${BIN_DIR}/sutra_update.py' '${BIN_DIR}/sutra_update.version' '${DATA_HOME}/${APP_ID}/allowed_signers'; do
    grep -qF "${want}" "${ROOT_DIR}/install.sh" || { bad "install.sh missing ${want}"; src_ok=0; }
done
[[ "${src_ok}" -eq 1 ]] && ok "install.sh ships sutra_update.py + allowed_signers (source layout)"

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
