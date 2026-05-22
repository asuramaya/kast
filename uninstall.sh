#!/usr/bin/env bash
set -uo pipefail

# Removes everything install.sh adds for the current user. It does NOT remove
# the apt packages (pipewire, avahi, uxplay, ...) since they are shared system
# components. User config/state is kept unless --purge is given.

APP_ID="kast"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BIN_DIR="${HOME}/.local/bin"
PURGE=0

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [--purge]
  --purge   also remove user config and state (~/.config/kast, ~/.local/state/kast)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge) PURGE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

note() { printf '%s\n' "$*"; }

stop_services() {
    # Current kast units plus any legacy ctrlk-cast units from before the rename.
    local units=(kast-tray.service uxplay.service uxplay-window-controller.service ctrlk-cast-tray.service)
    systemctl --user disable --now "${units[@]}" >/dev/null 2>&1 || true
}

kill_tray() {
    # Legacy AppIndicator tray may run outside its unit; stop it directly too.
    local p
    while read -r p; do
        [[ -n "${p}" ]] || continue
        if tr '\0' ' ' < "/proc/${p}/cmdline" 2>/dev/null | grep -qE 'kast-tray|ctrlk-cast-tray'; then
            kill "${p}" >/dev/null 2>&1 || true
        fi
    done < <(pgrep -x python3 2>/dev/null || true)
}

disable_extension() {
    command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions disable kast@asuramaya >/dev/null 2>&1 || true
    command -v gsettings >/dev/null 2>&1 || return 0
    # Drop the uuid from the enabled-extensions list (preserve the others).
    local current
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo '@as []')"
    if grep -Fq "'kast@asuramaya'" <<<"${current}"; then
        current="$(python3 - "${current}" <<'PY' 2>/dev/null || printf '%s' "${current}"
import ast, sys
try:
    items = [x for x in ast.literal_eval(sys.argv[1]) if x != "kast@asuramaya"]
except Exception:
    items = []
print(repr(items) if items else "@as []")
PY
)"
        gsettings set org.gnome.shell enabled-extensions "${current}" >/dev/null 2>&1 || true
    fi
}

remove_files() {
    rm -f "${BIN_DIR}/kast" "${BIN_DIR}/kast-tray"
    rm -f "${BIN_DIR}/ctrlk-cast" "${BIN_DIR}/ctrlk-cast-tray"
    rm -f "${CONFIG_HOME}/systemd/user/kast-tray.service" \
          "${CONFIG_HOME}/systemd/user/uxplay.service" \
          "${CONFIG_HOME}/systemd/user/uxplay-window-controller.service" \
          "${CONFIG_HOME}/systemd/user/ctrlk-cast-tray.service"
    rm -f "${DATA_HOME}/applications/kast-center.desktop" \
          "${DATA_HOME}/applications/kast-tray.desktop" \
          "${DATA_HOME}/applications/ctrlk-cast-center.desktop" \
          "${DATA_HOME}/applications/ctrlk-cast-tray.desktop"
    rm -rf "${DATA_HOME:?}/${APP_ID:?}" "${DATA_HOME:?}/ctrlk-cast"
    rm -rf "${DATA_HOME:?}/gnome-shell/extensions/kast@asuramaya"
    rm -f "${CONFIG_HOME}/pipewire/pipewire.conf.d/50-raop.conf"
}

remove_shortcut() {
    command -v gsettings >/dev/null 2>&1 || return 0
    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local current path
    current="$(gsettings get "${schema}" custom-keybindings 2>/dev/null || echo "@as []")"
    for path in \
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${APP_ID}/" \
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ctrlk-cast/"; do
        if grep -Fq "${path}" <<<"${current}"; then
            gsettings reset-recursively "${schema}.custom-keybinding:${path}" >/dev/null 2>&1 || true
            # Drop this path from the list, preserving any other custom bindings.
            current="$(python3 - "${current}" "${path}" <<'PY' 2>/dev/null || printf '%s' "${current}"
import ast, sys
try:
    items = ast.literal_eval(sys.argv[1])
except Exception:
    items = []
items = [x for x in items if x != sys.argv[2]]
print(repr(items) if items else "@as []")
PY
)"
        fi
    done
    gsettings set "${schema}" custom-keybindings "${current}" >/dev/null 2>&1 || true
}

remove_user_data() {
    [[ "${PURGE}" -eq 1 ]] || return 0
    rm -rf "${CONFIG_HOME:?}/${APP_ID:?}" "${STATE_HOME:?}/${APP_ID:?}"
    rm -rf "${CONFIG_HOME:?}/ctrlk-cast" "${STATE_HOME:?}/ctrlk-cast"
}

note "Removing kast..."
stop_services
kill_tray
disable_extension
remove_files
remove_shortcut
remove_user_data
systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1 || true

note "kast removed."
if [[ "${PURGE}" -eq 0 ]]; then
    note "User config kept at ${CONFIG_HOME}/${APP_ID} (use --purge to remove it)."
fi
note "Apt packages were left installed; remove them yourself if you no longer need them:"
note "  pipewire/avahi/uxplay/gnome-network-displays etc. (see packages.txt)"
