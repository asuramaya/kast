#!/usr/bin/env bash
set -euo pipefail

# Tolerate being read from stdin (curl ... | bash): BASH_SOURCE[0] is unset then.
_kast_src="${BASH_SOURCE[0]:-$0}"
ROOT_DIR="$(cd "$(dirname "${_kast_src}")" 2>/dev/null && pwd)" || ROOT_DIR=""
ROOT_DIR="${ROOT_DIR:-$PWD}"
REPO_SLUG="asuramaya/kast"
APP_ID="kast"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_DIR="${HOME}/.local/bin"
SHORTCUT="${KAST_SHORTCUT:-<Super>k}"
SKIP_APT=0
SKIP_SHORTCUT=0
PACKAGE_STATUS_NOTE=""

bootstrap_from_release() {
    # Reached when install.sh runs without its sibling files next to it, i.e.
    # piped from curl. Fetch the published tarball (falling back to main) and
    # re-exec the real installer from the extracted tree.
    command -v curl >/dev/null 2>&1 || { printf 'curl is required for remote install\n' >&2; exit 1; }
    command -v tar  >/dev/null 2>&1 || { printf 'tar is required for remote install\n' >&2; exit 1; }
    local tmp tarball inner
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    tarball="${tmp}/kast.tar.gz"
    printf 'Fetching latest kast release...\n'
    if ! curl -fsSL "https://github.com/${REPO_SLUG}/releases/latest/download/kast.tar.gz" -o "${tarball}"; then
        printf 'No release asset yet; using the main branch.\n'
        curl -fsSL "https://github.com/${REPO_SLUG}/archive/refs/heads/main.tar.gz" -o "${tarball}" \
            || { printf 'Download failed.\n' >&2; exit 1; }
    fi
    tar -xzf "${tarball}" -C "${tmp}"
    inner="$(find "${tmp}" -maxdepth 2 -name install.sh -type f | head -n1)"
    [[ -n "${inner}" ]] || { printf 'install.sh not found in archive\n' >&2; exit 1; }
    # Run (don't exec) so the EXIT trap above can clean up the temp checkout.
    bash "${inner}" "$@"
    exit $?
}

if [[ ! -f "${ROOT_DIR}/scripts/kast" ]]; then
    bootstrap_from_release "$@"
fi

KAST_VERSION="$(sed -n 's/^KAST_VERSION="\(.*\)"$/\1/p' "${ROOT_DIR}/scripts/kast" 2>/dev/null)"
KAST_VERSION="${KAST_VERSION:-unknown}"

EXT_UUID="kast@asuramaya"
EXT_DIR="${DATA_HOME}/gnome-shell/extensions/${EXT_UUID}"

usage() {
    cat <<'EOF'
Usage: ./install.sh [--skip-apt] [--no-shortcut] [--shortcut '<Super>k']
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-apt)
            SKIP_APT=1
            ;;
        --no-shortcut)
            SKIP_SHORTCUT=1
            ;;
        --shortcut)
            shift
            SHORTCUT="${1:-}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

install_packages() {
    mapfile -t packages < <(grep -Ev '^\s*(#|$)' "${ROOT_DIR}/packages.txt")
    sudo apt-get update
    # `--` stops a stray/crafted packages.txt line (e.g. "-o ...") from being
    # parsed as an apt option instead of a package name.
    sudo apt-get install -y -- "${packages[@]}"
}

install_user_files() {
    mkdir -p "${BIN_DIR}"
    install -D -m 644 "${ROOT_DIR}/config/pipewire/50-raop.conf" "${CONFIG_HOME}/pipewire/pipewire.conf.d/50-raop.conf"
    install -D -m 755 "${ROOT_DIR}/scripts/kast" "${BIN_DIR}/kast"
    if [[ ! -f "${CONFIG_HOME}/${APP_ID}/uxplay.conf" ]]; then
        install -D -m 644 "${ROOT_DIR}/config/uxplay.conf.example" "${CONFIG_HOME}/${APP_ID}/uxplay.conf"
    fi
    install -D -m 644 "${ROOT_DIR}/systemd/user/uxplay.service" "${CONFIG_HOME}/systemd/user/uxplay.service"
    install -D -m 644 "${ROOT_DIR}/applications/kast-center.desktop" "${DATA_HOME}/applications/kast-center.desktop"
    # GNOME Quick Settings extension — the primary UI.
    install -D -m 644 "${ROOT_DIR}/shell-extension/${EXT_UUID}/extension.js" "${EXT_DIR}/extension.js"
    install -D -m 644 "${ROOT_DIR}/shell-extension/${EXT_UUID}/prefs.js" "${EXT_DIR}/prefs.js"
    install -D -m 644 "${ROOT_DIR}/shell-extension/${EXT_UUID}/metadata.json" "${EXT_DIR}/metadata.json"
}

remove_legacy_tray() {
    # The AppIndicator tray was replaced by the Quick Settings extension.
    systemctl --user disable --now kast-tray.service >/dev/null 2>&1 || true
    pkill -f "${BIN_DIR}/kast-tray" >/dev/null 2>&1 || true
    rm -f "${CONFIG_HOME}/systemd/user/kast-tray.service" \
          "${BIN_DIR}/kast-tray" \
          "${DATA_HOME}/applications/kast-tray.desktop"
}

enable_services() {
    systemctl --user daemon-reload
    # The receiver is a LAN-facing listener, so it ships OFF by default: installed
    # but neither enabled nor started. Turn it on from the Kast tile (or
    # `kast receiver-start`) only when you actually want to receive.
    systemctl --user disable uxplay.service >/dev/null 2>&1 || true
    if ! command -v uxplay >/dev/null 2>&1; then
        PACKAGE_STATUS_NOTE="uxplay is not installed yet; the AirPlay receiver is unavailable."
    fi
    systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service || true
}

enable_extension() {
    # `gnome-extensions enable` refuses an extension the running shell hasn't
    # scanned yet (true right after a fresh install), so also write the
    # enabled-extensions gsettings list directly. The shell honors it on the
    # next login (Wayland cannot hot-reload shell extensions).
    command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions enable "${EXT_UUID}" >/dev/null 2>&1 || true
    command -v gsettings >/dev/null 2>&1 || return 0
    local current
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo '@as []')"
    if ! grep -Fq "'${EXT_UUID}'" <<<"${current}"; then
        if [[ "${current}" == "@as []" || "${current}" == "[]" ]]; then
            current="['${EXT_UUID}']"
        else
            current="${current%]}, '${EXT_UUID}']"
        fi
        gsettings set org.gnome.shell enabled-extensions "${current}" >/dev/null 2>&1 || true
    fi
}

enable_desktop_integration() {
    if [[ "${SKIP_SHORTCUT}" -eq 0 ]]; then
        "${BIN_DIR}/kast" install-shortcut "${SHORTCUT}" || true
    fi
}

if [[ "${SKIP_APT}" -eq 0 ]]; then
    install_packages
fi

install_user_files
remove_legacy_tray
enable_services
enable_extension
enable_desktop_integration

if ! grep -Fq "${BIN_DIR}" <<<":${PATH}:"; then
    PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }${BIN_DIR} is not on your PATH; add it to use the 'kast' command directly."
fi

SHORTCUT_LABEL="${SHORTCUT//</}"
SHORTCUT_LABEL="${SHORTCUT_LABEL//>/+}"

cat <<EOF

Kast v${KAST_VERSION} installed.

  *** Log out and back in to load the Kast tile in GNOME Quick Settings. ***
      (Wayland can't hot-reload shell extensions.)

  - UI:        the Kast tile in the Quick Settings menu (top-right)
  - Shortcut:  press ${SHORTCUT_LABEL} to open display casting
  - Check it:  kast doctor
  - Cast:      kast open-display-cast        (Chromecast / LAN: keeps Wi-Fi)
               kast open-display-cast --drop-wifi   (Miracast)
  - Receiver:  OFF by default (it is a LAN listener). Turn it on from the Kast
               tile when you want to receive; it is PIN-gated when on.
  - Update:    kast update
  - Remove:    curl -fsSL https://raw.githubusercontent.com/${REPO_SLUG}/main/uninstall.sh | bash
EOF

if [[ -n "${PACKAGE_STATUS_NOTE}" ]]; then
    printf '\nNote: %s\n' "${PACKAGE_STATUS_NOTE}"
fi
