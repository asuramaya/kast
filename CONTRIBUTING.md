# Contributing to kast

Kast is a small, pragmatic wrapper around the casting tools Ubuntu already ships.
Contributions that keep it simple and dependency-light are very welcome.

Before changing much, read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). It explains why the
CLI is the source of truth and the extension only renders, which is the decision most likely
to bite you if you don't know about it.

## Setup

```bash
git clone https://github.com/asuramaya/kast
cd kast
./install.sh --skip-apt   # if you already have the packages in packages.txt
kast doctor               # confirm the stack is healthy
```

Iterate on `bin/kast` directly with `bash bin/kast <verb>`, then re-run
`./install.sh --skip-apt` to refresh the installed copy.

The extension can't be hot-reloaded on Wayland. Either reinstall and log out and back in, or
test in a nested session:

```bash
dbus-run-session -- gnome-shell --nested --wayland
```

## The checks

Same ones CI runs:

```bash
make check          # shellcheck, py_compile, node --check, metadata JSON
make check-sutra    # the vendored update spine still matches canonical, byte for byte
make smoke          # end to end, against a throwaway XDG home and runtime dir
```

`make check` already depends on `check-sutra`, so running it covers both. `make attack` exists
and reports that Kast is exempt: there's no daemon and no socket of its own to fuzz.

If `check-sutra` reports lag, the shared `sutra` repo has moved ahead. Re-vendor rather than
editing `bin/sutra_update.py` in place. It's vendored byte-identical on purpose, and hand
edits are exactly what the integrity check exists to catch.

`make smoke` never touches your real installation. It runs against an overridden
`XDG_RUNTIME_DIR` and a throwaway home, so it's safe on the machine you actually use Kast on.

## Style

Bash runs under `set -euo pipefail` and stays ShellCheck-clean. Intentional exceptions belong
in `.shellcheckrc`, not scattered inline. Quote your expansions, and prefer small functions.

Keep new runtime dependencies out unless Ubuntu already ships them. The two pipx-isolated
Python helpers are the exception, and they're isolated precisely so they can't drag anything
into the user's environment.

The CLI is the integration point. When the tile needs something new, the CLI grows a verb with
`--json` output and the tile calls it. Logic living in the extension is logic nobody can test
from a terminal.

Device names come off the network and are attacker-controlled. They reach `jq` and UI labels
as text only.

## Pull requests

Open one against `main`. CI has to pass. If you change behaviour, update
[docs/USAGE.md](docs/USAGE.md), `data/man/man1/kast.1` if the verb it describes changed, and add a
`CHANGELOG.md` entry. Small, focused PRs get looked at fastest.

Each document has an owner, and it's worth a moment to put a change in the right one.
`README.md` answers what a stranger needs before installing. `docs/USAGE.md` covers everything
after. `docs/ARCHITECTURE.md` explains how it's built. A fact that lands in two of them will
drift.

## Releasing

Not covered here. See [docs/RELEASING.md](docs/RELEASING.md), because a release involves a
hardware key and a person, and getting the order wrong can break the update path for everyone
who already installed.
