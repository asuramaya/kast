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
    exec bash "${inner}" "$@"
}

if [[ ! -f "${ROOT_DIR}/scripts/kast" ]]; then
    bootstrap_from_release "$@"
fi

KAST_VERSION="$(sed -n 's/^KAST_VERSION="\(.*\)"$/\1/p' "${ROOT_DIR}/scripts/kast" 2>/dev/null)"
KAST_VERSION="${KAST_VERSION:-unknown}"

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
    sudo apt-get install -y "${packages[@]}"
}

install_user_files() {
    mkdir -p "${BIN_DIR}"
    install -D -m 644 "${ROOT_DIR}/config/pipewire/50-raop.conf" "${CONFIG_HOME}/pipewire/pipewire.conf.d/50-raop.conf"
    install -D -m 755 "${ROOT_DIR}/scripts/kast" "${BIN_DIR}/kast"
    install -D -m 755 "${ROOT_DIR}/scripts/kast-tray.py" "${BIN_DIR}/kast-tray"
    if [[ ! -f "${CONFIG_HOME}/${APP_ID}/uxplay.conf" ]]; then
        install -D -m 644 "${ROOT_DIR}/config/uxplay.conf.example" "${CONFIG_HOME}/${APP_ID}/uxplay.conf"
    fi
    install -D -m 644 "${ROOT_DIR}/systemd/user/uxplay.service" "${CONFIG_HOME}/systemd/user/uxplay.service"
    install -D -m 644 "${ROOT_DIR}/systemd/user/kast-tray.service" "${CONFIG_HOME}/systemd/user/kast-tray.service"
    install -D -m 644 "${ROOT_DIR}/applications/kast-center.desktop" "${DATA_HOME}/applications/kast-center.desktop"
    cat >"${DATA_HOME}/applications/kast-tray.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kast Tray
Comment=Top bar controls for casting and AirPlay receiver state
Exec=${BIN_DIR}/kast-tray
Icon=video-display-symbolic
Terminal=false
Categories=AudioVideo;Network;GNOME;
StartupNotify=false
EOF
}

enable_services() {
    systemctl --user daemon-reload
    systemctl --user enable kast-tray.service
    systemctl --user restart kast-tray.service
    if command -v uxplay >/dev/null 2>&1; then
        systemctl --user enable uxplay.service
        systemctl --user start uxplay.service
    else
        systemctl --user disable --now uxplay.service >/dev/null 2>&1 || true
        PACKAGE_STATUS_NOTE="uxplay and other apt-managed pieces are not installed yet."
        printf 'Skipping uxplay startup because the package is not installed.\n'
    fi
    systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service || true
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
enable_services
enable_desktop_integration

if ! grep -Fq "${BIN_DIR}" <<<":${PATH}:"; then
    PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }${BIN_DIR} is not on your PATH; add it to use the 'kast' command directly."
fi

SHORTCUT_LABEL="${SHORTCUT//</}"
SHORTCUT_LABEL="${SHORTCUT_LABEL//>/+}"

cat <<EOF

Kast v${KAST_VERSION} installed.

  - Tray:      look for the cast icon in the top bar (next to network/sound)
  - Shortcut:  press ${SHORTCUT_LABEL} to open display casting
  - Check it:  kast doctor
  - Cast:      kast open-display-cast        (Chromecast / LAN: keeps Wi-Fi)
               kast open-display-cast --drop-wifi   (Miracast)
  - Discover:  kast cast-targets    kast miracast-targets
  - Remove:    ./uninstall.sh
EOF

if [[ -n "${PACKAGE_STATUS_NOTE}" ]]; then
    printf '\nNote: %s\n' "${PACKAGE_STATUS_NOTE}"
fi
