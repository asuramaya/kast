# kast — the status.json seam (design only, nothing here is implemented)

Doctrine point 4: a status.json the pill and CLI read, with the machinery
below the seam. Every sibling satisfies it with a daemon that owns the truth;
kast is the family's one exempt glue layer — it HAS no daemon, and its truth
is scattered across avahi's cache, `systemctl --user`, and
gnome-network-displays. The seam still applies: one file, one shape, and
where the truth comes *from* stays below it. Today the pill re-derives that
truth by shelling out to `kast … --json` on a 10s status timer, a 20s
discovery timer, and every menu open — a bash+avahi-browse+jq+systemctl
subprocess fan-out per tick, and a blocking one at the moment you look.

## What belongs in it

```json
{ "version": 1, "written_at": 1770000000,
  "receivers": { "airplay_screen": "active", "airplay_audio": "inactive",
                 "youtube": "inactive", "checked_at": 1770000000 },
  "devices": [ { "name": "Living Room TV", "kind": "airplay",
                 "addr": "…", "discovered_at": 1769999940 } ],
  "session": { "active": true, "target": "Living Room TV",
               "via": "gnd", "since": 1769999900 } }
```

- **receivers** — `systemctl --user is-active` on the three off-by-default
  units (uxplay / shairport-sync / kast-youtube), verbatim, plus when asked.
- **devices** — the cached avahi read the tile already renders, each entry
  aged with `discovered_at`. The cache is the seed, never the master: a
  fresh `--scan` refreshes it, the seam only reports it.
- **session** — the active cast + target (the `gnd-stream-unit` state file,
  or the live pyatv/catt cast), `via` naming the path.
- **ages everywhere** — `written_at` plus per-section timestamps. A reader
  judges staleness itself; a stale seam degrades to "unknown", never lies.

## Where it lives

`$XDG_RUNTIME_DIR/kast/status.json` — dir 0700, file 0640, written
atomically (tmp + rename, doctrine 4). The runtime dir dies with the
session, so a stale file cannot outlive the login that wrote it; nothing
lands in `~/.local/state`, which stays for durable seeds (mode, pairing).

## Who writes it (candidates)

| candidate | verdict |
|---|---|
| the `kast` CLI, on every verb that computes truth | **yes** — the actor that just changed or read the state writes it, no new process, no new unit |
| a `kast-status` oneshot on a user timer | no — a poller that wakes even when nothing casts and nobody looks, to duplicate reads the tile already triggers |
| a thin `kastd --user` | no — a daemon for a glue layer is the exemption revoked in the wrong direction; it would be the oneshot poller wearing a service file |

Concretely: every state-changing verb (`connect`, `disconnect`, `cast-file`,
`receiver-*`, `audio-receiver-*`, `youtube-receiver-*`) and the read verbs
that already assemble the truth (`status`, `targets`) end by writing the
seam as a by-product. External drift — a receiver crashing, a device
powering off — is caught by the pill's *existing* timers, which keep firing
`kast status --json` / `targets --json`; those runs now refresh the file too.

## What the pill gains

Menu-open renders the device list from the file instantly — no blocking
discovery subprocess at the moment of interaction; `discovered_at` ages let
it grey entries instead of dropping them. The 10s/20s timers become the
freshness engine rather than the render path, and a Gio.FileMonitor on the
seam makes verb-driven changes (a cast started from the CLI, a receiver
toggled) appear in the tile the second they happen, between ticks.

## Recommendation

CLI-as-writer. One `write_status_seam()` in `bin/kast` (assemble JSON, tmp +
rename, 0640) hooked at the tail of the verbs above; extension.js grows a
file monitor and reads the seam first, falling back to today's shell-out
when the file is absent (older CLI, first run). Milestone-sized: ~150 lines
of bash, ~60 lines of GJS, smoke additions asserting the shape (doctrine 7)
and the atomic write; no new units, no new dependencies, fully backward
compatible — one focused milestone, nothing more.
