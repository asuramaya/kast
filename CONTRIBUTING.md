# Contributing to kast

Thanks for your interest! kast is a small, pragmatic wrapper around native Ubuntu
casting tools. Contributions that keep it simple and dependency-light are very welcome.

## Project layout

| Path | What |
|------|------|
| `scripts/kast` | the CLI (bash); the source of truth, run by every other piece |
| `scripts/kast-tray.py` | AppIndicator tray (Python + GTK3) |
| `shell-extension/kast@asuramaya/` | optional GNOME Shell panel UI (GJS) |
| `install.sh` / `uninstall.sh` | user-scope (de)installer |
| `systemd/user/`, `config/`, `applications/` | installed unit/config/desktop files |

## Dev setup

```bash
git clone https://github.com/asuramaya/kast
cd kast
./install.sh --skip-apt   # if you already have the packages from packages.txt
kast doctor               # confirm the stack is healthy
```

Iterate on `scripts/kast` directly (`bash scripts/kast <cmd>`), then re-run
`./install.sh --skip-apt` to update the installed copy.

## Run the checks locally (same as CI)

```bash
shellcheck install.sh uninstall.sh scripts/kast      # reads .shellcheckrc
python3 -m py_compile scripts/kast-tray.py
python3 -m pyflakes scripts/kast-tray.py
node --check shell-extension/kast@asuramaya/extension.js
bash scripts/kast version && bash scripts/kast --help
```

## Style

- Bash: `set -euo pipefail`, keep it ShellCheck-clean (intentional exceptions live in
  `.shellcheckrc`). Quote expansions. Prefer small functions.
- Keep new runtime dependencies out unless they already ship on Ubuntu 25.10.
- The CLI is the integration point: tray and extension shell out to `kast … --json`.

## Releasing

1. Bump `KAST_VERSION` in `scripts/kast`.
2. Add a `CHANGELOG.md` entry.
3. Tag `vX.Y.Z` and push it — `release.yml` asserts the tag matches `KAST_VERSION`,
   builds `kast.tar.gz` + `.sha256`, and publishes a GitHub Release.

## Pull requests

Open a PR against `main`. CI must pass. If you change behaviour, update the README and
`CHANGELOG.md`. Small, focused PRs get reviewed fastest.
