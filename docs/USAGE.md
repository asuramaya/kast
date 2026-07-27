# Using Kast

Everything the CLI, the tile and the preferences dialog can do. If you just installed
Kast, start with `kast doctor`. For the short version, see the
[README](../README.md).

Almost every command that prints something accepts `--json`, which is how the GNOME
extension talks to the CLI.

## Finding a device

```bash
kast targets                  # everything known, from the avahi cache (fast)
kast targets --scan           # fresh mDNS queries instead of the cache (slower, current)
kast cast-targets             # Chromecast only
kast airplay-targets          # AirPlay only
kast miracast-targets         # Miracast, an on-demand Wi-Fi P2P find
```

Discovery for Chromecast and AirPlay is mDNS. Cached reads keep the UI responsive, and the
tile refreshes in the background and whenever you open "Cast to…". Miracast is different:
finding it means a Wi-Fi P2P scan that shares your radio, so nothing polls for it. You ask,
it looks.

## Casting

```bash
kast pick                          # the graphical picker (Super+K)
kast pick --miracast               # the picker, including a Miracast scan
kast connect <name|address>        # mirror this screen to a device
kast connect <name> <url-or-file>  # connect and play something instead of mirroring
kast cast-file <target> <url-or-file>
kast display-connect <name>        # display mirroring specifically
kast disconnect                    # stop the active display stream
```

Two different paths hide behind these verbs, and it's worth knowing which you're on.
Screen mirroring goes through `gnome-network-displays` to Chromecast and Miracast. Playing a
file or a URL goes through `pyatv` for AirPlay and `catt` for Chromecast, and it doesn't
mirror anything; the device fetches and plays the media itself.

Casting to an AirPlay TV for the first time may need a one-off pairing:

```bash
kast airplay-pair <target>          # pair, prompting in the terminal
kast airplay-pair <target> --gui    # pair with a graphical prompt
```

`kast airplay-pick <target>` and `kast cast-file-pick <target>` open a file picker and then
cast whatever you chose, the first restricted to AirPlay, the second to any target. The tile
uses these; from a terminal, `cast-file` with a path you already know is usually quicker.

## Controlling what you're casting to

```bash
kast control                                # list controllable devices
kast control <target> caps                  # what this device actually supports
kast control <target> now-playing
kast control <target> <action> [arg]
kast control-center [<target>]              # the graphical remote
```

Actions: `stop`, `play`, `pause`, `play_pause`, `next`, `previous`, `seek <seconds>`,
`volume_up`, `volume_down`, `set_volume <0-100>`, `power_on`, `power_off`,
`key <up|down|left|right|select|menu|home>`, `launch_app <id>`.

The control surface is capability-driven, so it reflects the device rather than a fixed
menu. An AirPlay-only TV exposes stop and volume. An Apple TV gives you the full remote,
including transport, navigation, power and now-playing. `kast control <target> caps` is the
honest answer to "what can I do with this thing".

## Receiving

Three receivers, all off by default, all LAN-facing listeners. Each has the same six verbs.

| Receiver | What it accepts | Backed by |
|---|---|---|
| `receiver-*` | AirPlay screen mirroring in | `uxplay` |
| `audio-receiver-*` | AirPlay audio in | `shairport-sync` |
| `youtube-receiver-*` | YouTube and YT-Music over DIAL | `yt-cast-receiver` and `mpv` |

```bash
kast receiver-start | receiver-stop | receiver-restart | receiver-status
kast toggle-receiver
kast receiver-run          # run in the foreground, for debugging
```

Substitute `audio-receiver-` or `youtube-receiver-` for the other two. The tile shows
switches for whichever ones have their dependencies installed.

The AirPlay screen receiver is PIN-gated by default. A sender has to type the 4-digit PIN
shown on screen before it can mirror. Treat that as a speed bump and not as authentication;
stopping the receiver when you aren't using it is the control that actually protects you.

## Audio routing

```bash
kast sinks                     # available audio sinks
kast select-sink <id|name>     # route audio to a specific sink
kast select-airplay [name]     # route to an AirPlay speaker over PipeWire RAOP
kast select-local              # route back to this machine
kast open-sound                # open GNOME's Sound settings
```

Routing during a normal cast is left to GNOME's own Sound menu on purpose. These verbs exist
for AirPlay audio out and for scripting.

## Display behaviour

```bash
kast set-mode <mirror|video-overlay>
kast get-mode
kast open-display                       # GNOME Display settings
kast open-display-cast [--drop-wifi]    # the gnome-network-displays picker
kast reconnect-wifi                     # bring Wi-Fi back after a Miracast session
```

Miracast wants the Wi-Fi radio, so a cast can drop your network connection. `--drop-wifi`
makes that deliberate, and `reconnect-wifi` puts it back. The default behaviour is set in
preferences.

`kast open-display-cast-plain` opens the `gnome-network-displays` GUI directly, skipping the
one-click D-Bus path. It's what Kast falls back to on a GNOME Shell older than the daemon
that path needs (see Troubleshooting below), and it still works fine by hand.

## Health and updates

```bash
kast status [--json]     # what's casting, what's receiving, what's discovered
kast doctor              # full health check, with a fix hint per problem
kast repair              # reinstall the pyatv and catt venvs
kast version
kast check-update
kast update [--apt]
kast update --check
kast install-shortcut [binding]
```

`kast doctor` is the first thing to run when anything misbehaves. It checks tools,
discovery, the receivers, outbound casting, audio routing and desktop integration, and for
each problem it prints what to do about it.

`kast repair` exists for one specific failure: an Ubuntu or Python upgrade leaves the
pipx-isolated `pyatv` and `catt` environments pointing at a Python that's gone. Casting a
file starts failing, `doctor` reports the broken venv, and `repair` rebuilds it.

## The Quick Settings tile

Open the system menu at the top right. The **Kast** tile sits next to Wi-Fi and Bluetooth.
Clicking it opens the picker; the ⌄ expands a menu built around collapsible groups:

* **Casting · &lt;target&gt;** with **Disconnect**, shown only while a stream is live.
* **Cast to…**, collapsible: discovered Chromecast and AirPlay devices, Miracast targets
  after a scan, plus **Open picker…**, **Scan for Miracast** and **Rescan**.
* **Receive**, collapsible: on/off switches for the three receivers. Audio and YouTube
  appear only when their dependencies are installed.
* **Control Center…**, which opens the remote for a controllable device.
* **Kast Settings…**, the preferences dialog.
* The installed version, and an **⬆ Update** entry when a new release exists.

The tile reads its state from a status file the CLI writes, so opening the menu is instant
rather than blocking on a discovery pass. [ARCHITECTURE.md](ARCHITECTURE.md) describes that
seam if you're curious about why the menu feels quick.

## Preferences

**Kast Settings…** in the tile, or `gnome-extensions prefs kast@asuramaya`, opens an Adwaita
dialog covering receiver names, mirror or video-overlay mode, H.265, require-PIN, and whether
casting drops Wi-Fi by default.

It writes `~/.config/kast/uxplay.conf`, which is the same file the CLI reads. You can edit
that file directly; start from
[config/uxplay.conf.example](../config/uxplay.conf.example). It's sourced like a
shell rc file, so treat it as code you own. The preferences dialog escapes everything it
writes there.

## Troubleshooting

Run `kast doctor` first. It diagnoses most of this list and tells you the fix.

**`kast: command not found`**
`~/.local/bin` isn't on your `PATH`. Add it, or log out and back in.

**No Kast tile in Quick Settings**
The extension only loads at a fresh login on Wayland. Log out and back in, then check
`gnome-extensions list --enabled | grep kast`.

**The tile vanished after a GNOME or Ubuntu upgrade**
A new GNOME Shell can flag the extension as out of date, and `kast doctor` will say so. Run
`kast update` to pick up metadata that supports the new shell, then log out and back in. In
the meantime `kast pick` and `Super+K` still give you the cast menu.

**No Miracast displays found**
Discovery is an on-demand Wi-Fi P2P find, and some adapters can't do P2P at all. `kast
doctor` reports that. Otherwise, try again closer to the display.

**An AirPlay or Chromecast cast fails**
Check `kast doctor` for a broken pyatv or catt venv, which is common after an OS upgrade, and
run `kast repair` if it reports one. If an AirPlay TV refuses the cast outright, pair it once
with `kast airplay-pair <target>`.

**The YouTube receiver switch is missing**
It needs `node` and `mpv`. Install them with `./install.sh --with-youtube`, then log out and
back in.

**One-click display connect isn't one click**
It needs `gnome-network-displays` 0.99.0 or newer, which is where the D-Bus daemon arrives.
Ubuntu 26.04 has it. On older versions Kast falls back to the GUI picker, which still works.
