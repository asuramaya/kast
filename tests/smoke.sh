#!/usr/bin/env bash
# Smoke tests for the kast CLI: exercise the no-hardware-needed paths and assert
# they don't crash, emit valid JSON where promised, and round-trip state. Safe to
# run anywhere — it points kast at a throwaway XDG home so it never touches real
# config/state. Discovery returns an empty set without an avahi daemon, which is
# itself the contract we check. Run: bash tests/smoke.sh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAST=(bash "${ROOT_DIR}/scripts/kast")

# Sandbox all reads/writes into a temp XDG tree.
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}"' EXIT
export XDG_CONFIG_HOME="${TMP_HOME}/config"
export XDG_STATE_HOME="${TMP_HOME}/state"
export XDG_DATA_HOME="${TMP_HOME}/data"

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

# --- state round-trips (no hardware) ---
expect_grep  "get-mode defaults to mirror"   "mirror" "${KAST[@]}" get-mode
"${KAST[@]}" set-mode video-overlay >/dev/null 2>&1
expect_grep  "set-mode persists"             "video-overlay" "${KAST[@]}" get-mode
"${KAST[@]}" set-mode mirror >/dev/null 2>&1
expect_fail  "set-mode rejects bad mode"     "${KAST[@]}" set-mode bogus

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
