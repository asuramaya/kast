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
WITH_YOUTUBE=0
WITH_AIRPLAY_AUDIO=0
PACKAGE_STATUS_NOTE=""

verify_release_tarball() {
    # Verify the downloaded release tarball against its published SHA-256 asset
    # (kast.tar.gz.sha256, content "<hash>  kast.tar.gz") before we extract and
    # execute it. We refuse rather than fall back to "unverified" here: the
    # release path is supposed to be verifiable, so a missing checksum or a
    # mismatch means something is wrong, not that we should trust it anyway.
    # (The main-branch fallback has no such asset and is gated by its own loud
    # warning + KAST_NO_UNSTABLE instead.)
    local tarball="$1" want got
    command -v sha256sum >/dev/null 2>&1 || {
        printf 'sha256sum not found; cannot verify the release download. Install coreutils and retry.\n' >&2
        exit 1
    }
    want="$(curl -fsSL "https://github.com/${REPO_SLUG}/releases/latest/download/kast.tar.gz.sha256" 2>/dev/null \
        | awk '$2 == "kast.tar.gz" { print $1; exit }')"
    if [[ -z "${want}" ]]; then
        printf 'Could not fetch the release checksum (kast.tar.gz.sha256); refusing to install an unverified download.\n' >&2
        exit 1
    fi
    got="$(sha256sum "${tarball}" | awk '{ print $1 }')"
    if [[ "${want}" != "${got}" ]]; then
        printf 'Checksum mismatch on kast.tar.gz (expected %s, got %s); aborting.\n' "${want}" "${got}" >&2
        exit 1
    fi
    printf 'Verified release checksum.\n'
}

bootstrap_from_release() {
    # Reached when install.sh runs without its sibling files next to it, i.e.
    # piped from curl. Fetch the published tarball (falling back to main) and
    # re-exec the real installer from the extracted tree.
    command -v curl >/dev/null 2>&1 || { printf 'curl is required for remote install\n' >&2; exit 1; }
    command -v tar  >/dev/null 2>&1 || { printf 'tar is required for remote install\n' >&2; exit 1; }
    local tmp tarball inner from_release=1
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    tarball="${tmp}/kast.tar.gz"
    printf 'Fetching latest kast release...\n'
    if ! curl -fsSL "https://github.com/${REPO_SLUG}/releases/latest/download/kast.tar.gz" -o "${tarball}"; then
        from_release=0
        printf '\n  WARNING: no published release asset found — falling back to the\n' >&2
        printf '  UNREVIEWED tip of the main branch. Set KAST_NO_UNSTABLE=1 to refuse this.\n\n' >&2
        [[ "${KAST_NO_UNSTABLE:-0}" == "1" ]] && { printf 'Refusing main-branch fallback (KAST_NO_UNSTABLE=1).\n' >&2; exit 1; }
        curl -fsSL "https://github.com/${REPO_SLUG}/archive/refs/heads/main.tar.gz" -o "${tarball}" \
            || { printf 'Download failed.\n' >&2; exit 1; }
    fi
    # Released tarballs are verified against their published checksum; the
    # main-branch fallback is inherently unverifiable (already warned above).
    [[ "${from_release}" -eq 1 ]] && verify_release_tarball "${tarball}"
    tar -xzf "${tarball}" -C "${tmp}"
    inner="$(find "${tmp}" -maxdepth 2 -name install.sh -type f | head -n1)"
    [[ -n "${inner}" ]] || { printf 'install.sh not found in archive\n' >&2; exit 1; }
    # Run (don't exec) so the EXIT trap above can clean up the temp checkout.
    bash "${inner}" "$@"
    exit $?
}

if [[ ! -f "${ROOT_DIR}/bin/kast" ]]; then
    bootstrap_from_release "$@"
fi

# The repo-root VERSION file is the source of truth; fall back to the value
# embedded in bin/kast for tarballs that predate the VERSION file.
if [[ -f "${ROOT_DIR}/VERSION" ]]; then
    KAST_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
else
    KAST_VERSION="$(sed -n 's/^KAST_VERSION="\(.*\)"$/\1/p' "${ROOT_DIR}/bin/kast" 2>/dev/null)"
fi
KAST_VERSION="${KAST_VERSION:-unknown}"

EXT_UUID="kast@asuramaya"
EXT_DIR="${DATA_HOME}/gnome-shell/extensions/${EXT_UUID}"

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]
  --skip-apt              don't touch apt (install kast files only)
  --no-shortcut           don't bind the Super+K shortcut
  --shortcut '<Super>k'   use a different shortcut
  --with-airplay-audio    also install shairport-sync (AirPlay audio receive)
  --with-youtube          also install nodejs/npm/mpv/yt-dlp (YouTube DIAL receive)
  --with-all              install every optional feature's dependencies

Core install gives outbound casting, AirPlay screen receive, the picker, and
(via pipx) AirPlay video-out + the control center. The receivers above are
opt-in because they pull heavier dependencies.
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
        --with-airplay-audio)
            WITH_AIRPLAY_AUDIO=1
            ;;
        --with-youtube)
            WITH_YOUTUBE=1
            ;;
        --with-all)
            WITH_AIRPLAY_AUDIO=1
            WITH_YOUTUBE=1
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
    # Strip CRLF so a Windows-checkout packages.txt doesn't yield names with a
    # trailing \r that apt then can't resolve.
    mapfile -t packages < <(grep -Ev '^\s*(#|$)' "${ROOT_DIR}/packages.txt" | tr -d '\r')
    # Optional feature dependencies, added only when their flag is set, so a
    # plain install stays lean.
    [[ "${WITH_AIRPLAY_AUDIO}" -eq 1 ]] && packages+=(shairport-sync)
    [[ "${WITH_YOUTUBE}" -eq 1 ]] && packages+=(nodejs npm mpv yt-dlp)
    sudo apt-get update
    # `--` stops a stray/crafted packages.txt line (e.g. "-o ...") from being
    # parsed as an apt option instead of a package name.
    sudo apt-get install -y -- "${packages[@]}"
}

install_gnd_dbus_service() {
    # D-Bus activation file so the session bus starts gnome-network-displays-daemon
    # on demand (first one-click connect), instead of kast spawning it itself.
    # Generated at install time so Exec points at the daemon's real path. Skipped
    # when the daemon isn't present; kast's runtime fallback still spawns it.
    local daemon_bin svc
    daemon_bin="$(command -v gnome-network-displays-daemon 2>/dev/null || true)"
    [[ -n "${daemon_bin}" ]] || return 0
    svc="${DATA_HOME}/dbus-1/services/org.gnome.NetworkDisplays.Daemon.service"
    install -D -m 644 "${ROOT_DIR}/dbus/org.gnome.NetworkDisplays.Daemon.service" "${svc}"
    # Escape sed replacement metacharacters (& | \) so an unusual install path
    # can't corrupt the Exec= line the session bus will run.
    local daemon_esc
    daemon_esc="$(printf '%s' "${daemon_bin}" | sed -e 's/[\\&|]/\\&/g')"
    sed -i "s|@DAEMON_BIN@|${daemon_esc}|" "${svc}"
}

install_user_files() {
    mkdir -p "${BIN_DIR}"
    install -D -m 644 "${ROOT_DIR}/config/pipewire/50-raop.conf" "${CONFIG_HOME}/pipewire/pipewire.conf.d/50-raop.conf"
    install -D -m 755 "${ROOT_DIR}/bin/kast" "${BIN_DIR}/kast"
    # AirPlay video-out helper + Adwaita control-center window (kast finds them
    # next to itself).
    install -D -m 755 "${ROOT_DIR}/bin/kast-airplay" "${BIN_DIR}/kast-airplay"
    install -D -m 755 "${ROOT_DIR}/bin/kast-control-center" "${BIN_DIR}/kast-control-center"
    if [[ ! -f "${CONFIG_HOME}/${APP_ID}/uxplay.conf" ]]; then
        install -D -m 644 "${ROOT_DIR}/config/uxplay.conf.example" "${CONFIG_HOME}/${APP_ID}/uxplay.conf"
    fi
    install -D -m 644 "${ROOT_DIR}/systemd/user/uxplay.service" "${CONFIG_HOME}/systemd/user/uxplay.service"
    install -D -m 644 "${ROOT_DIR}/systemd/user/shairport-sync.service" "${CONFIG_HOME}/systemd/user/shairport-sync.service"
    install -D -m 644 "${ROOT_DIR}/systemd/user/kast-youtube.service" "${CONFIG_HOME}/systemd/user/kast-youtube.service"
    install_gnd_dbus_service
    install -D -m 644 "${ROOT_DIR}/applications/kast-center.desktop" "${DATA_HOME}/applications/kast-center.desktop"
    # The desktop session's PATH may not include ~/.local/bin, so point the
    # launcher's Exec at the absolute kast path (escape sed metacharacters in case
    # $HOME contains & | or \).
    local exec_esc
    exec_esc="$(printf '%s' "${BIN_DIR}/kast " | sed -e 's/[\\&|]/\\&/g')"
    sed -i "s|^Exec=kast |Exec=${exec_esc}|" "${DATA_HOME}/applications/kast-center.desktop"
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
    # The receivers are LAN-facing listeners, so they ship OFF by default:
    # installed but neither enabled nor started. Turn them on from the Kast tile
    # (or kast receiver-start / audio-receiver-start) only when you want to receive.
    systemctl --user disable uxplay.service >/dev/null 2>&1 || true
    systemctl --user disable shairport-sync.service >/dev/null 2>&1 || true
    systemctl --user disable kast-youtube.service >/dev/null 2>&1 || true
    # The shairport-sync apt package ships an auto-started SYSTEM service; stop it
    # so it neither listens unexpectedly nor collides with kast's user service.
    if systemctl list-unit-files shairport-sync.service >/dev/null 2>&1; then
        sudo systemctl disable --now shairport-sync.service >/dev/null 2>&1 || true
    fi
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
    if command -v gnome-extensions >/dev/null 2>&1; then
        gnome-extensions enable "${EXT_UUID}" >/dev/null 2>&1 || true
    fi
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

install_youtube_receiver() {
    # The YouTube DIAL receiver is a small Node app; copy it to the data dir and
    # fetch its one dependency with npm. Best-effort — never fails the install.
    local dest="${DATA_HOME}/${APP_ID}/youtube-receiver"
    install -D -m 644 "${ROOT_DIR}/youtube-receiver/index.mjs" "${dest}/index.mjs"
    install -D -m 644 "${ROOT_DIR}/youtube-receiver/package.json" "${dest}/package.json"
    # Ship the lockfile so deps install reproducibly via `npm ci` (pinned to the
    # audited tree) rather than `npm install` (which can drift to newer versions).
    install -D -m 644 "${ROOT_DIR}/youtube-receiver/package-lock.json" "${dest}/package-lock.json"
    if command -v npm >/dev/null 2>&1; then
        ( cd "${dest}" && npm ci --omit=dev --no-audit --no-fund >/dev/null 2>&1 ) \
            || PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }YouTube receiver deps failed to install (run: cd ${dest} && npm ci)."
    else
        PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }npm not found; YouTube receiver needs Node.js (apt install nodejs npm) then re-run install."
    fi
    # Pre-seed kast's self-updating yt-dlp so the first cast doesn't wait on a
    # download. Best-effort; verify the SHA-256 before trusting the binary.
    if command -v curl >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1; then
        local yt_dlp_bin="${DATA_HOME}/${APP_ID}/bin/yt-dlp" yt_tmp yt_want yt_got
        mkdir -p "$(dirname "${yt_dlp_bin}")"
        yt_tmp="$(mktemp "${yt_dlp_bin}.XXXXXX")" || yt_tmp=""
        if [[ -n "${yt_tmp}" ]] && curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "${yt_tmp}"; then
            yt_want="$(curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS" 2>/dev/null | awk '$2 == "yt-dlp" { print $1; exit }')"
            yt_got="$(sha256sum "${yt_tmp}" | awk '{ print $1 }')"
            if [[ -n "${yt_want}" && "${yt_want}" == "${yt_got}" ]]; then
                chmod +x "${yt_tmp}"
                mv -f "${yt_tmp}" "${yt_dlp_bin}"
            else
                rm -f "${yt_tmp}"
                PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }yt-dlp checksum mismatch; skipped pre-seed (kast will retry at runtime)."
            fi
        else
            rm -f "${yt_tmp}"
        fi
    fi
}

install_pipx_tools() {
    # Optional, isolated via pipx (no apt): pyatv = AirPlay video-out + control
    # center; catt = Chromecast file/URL casting. Best-effort — never fails install.
    if ! command -v pipx >/dev/null 2>&1; then
        PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }pipx not found; for AirPlay video-out + Chromecast file-cast install it, then: pipx install pyatv catt."
        return 0
    fi
    if ! { "${HOME}/.local/share/pipx/venvs/pyatv/bin/python" -c 'import pyatv' >/dev/null 2>&1 || python3 -c 'import pyatv' >/dev/null 2>&1; }; then
        pipx install pyatv >/dev/null 2>&1 \
            || PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }pyatv install failed; AirPlay video-out unavailable (try: pipx install pyatv)."
    fi
    if ! command -v catt >/dev/null 2>&1; then
        pipx install catt >/dev/null 2>&1 \
            || PACKAGE_STATUS_NOTE="${PACKAGE_STATUS_NOTE:+${PACKAGE_STATUS_NOTE} }catt install failed; Chromecast file-cast unavailable (try: pipx install catt)."
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
install_pipx_tools
install_youtube_receiver

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
