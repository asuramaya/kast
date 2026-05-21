#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")

from gi.repository import AyatanaAppIndicator3 as AppIndicator3
from gi.repository import Gio, GLib, Gtk


APP_ID = "kast-tray"
CLI = str(Path.home() / ".local" / "bin" / "kast")
ICON_IDLE = "video-display-symbolic"
ICON_ACTIVE = "network-wireless-signal-excellent-symbolic"
REFRESH_SEC = 6
# mDNS discovery is slower and out-of-band, so it runs on its own cadence and
# never blocks the status refresh that rebuilds the menu.
CAST_DISCOVERY_SEC = 20
# Update checks hit the network; keep them infrequent.
UPDATE_CHECK_SEC = 6 * 3600


class KastCastTray:
    def __init__(self) -> None:
        self.indicator = AppIndicator3.Indicator.new(
            APP_ID,
            ICON_IDLE,
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Kast")
        self.indicator.set_icon_full(ICON_IDLE, "Kast")
        self._cast_targets: list[dict] = []
        self._miracast_targets: list[dict] = []
        self._miracast_scanning = False
        self._update_info: dict | None = None
        self._refresh()
        GLib.timeout_add_seconds(REFRESH_SEC, self._periodic_refresh)
        self._discover_cast_targets()
        GLib.timeout_add_seconds(CAST_DISCOVERY_SEC, self._discover_cast_targets)
        self._check_update()
        GLib.timeout_add_seconds(UPDATE_CHECK_SEC, self._check_update)

    def _periodic_refresh(self) -> bool:
        self._refresh()
        return GLib.SOURCE_CONTINUE

    def _discover_cast_targets(self) -> bool:
        # Run `kast cast-targets --json` off the main loop; the result lands in
        # _on_cast_targets, which caches it and rebuilds the menu.
        try:
            proc = Gio.Subprocess.new(
                [CLI, "cast-targets", "--json"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
            )
            proc.communicate_utf8_async(None, None, self._on_cast_targets)
        except Exception:
            pass
        return GLib.SOURCE_CONTINUE

    def _on_cast_targets(self, proc: Gio.Subprocess, result: Gio.AsyncResult) -> None:
        try:
            _ok, stdout, _stderr = proc.communicate_utf8_finish(result)
            targets = json.loads(stdout) if stdout else []
            if isinstance(targets, list):
                self._cast_targets = targets
                self._refresh()
        except Exception:
            pass

    def _scan_miracast(self) -> None:
        # On-demand only: a P2P find shares the Wi-Fi radio, so it is never run
        # on a timer. Shows a "Scanning…" state while the find runs.
        if self._miracast_scanning:
            return
        self._miracast_scanning = True
        self._refresh()
        try:
            proc = Gio.Subprocess.new(
                [CLI, "miracast-targets", "--json"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
            )
            proc.communicate_utf8_async(None, None, self._on_miracast_targets)
        except Exception:
            self._miracast_scanning = False
            self._refresh()

    def _on_miracast_targets(self, proc: Gio.Subprocess, result: Gio.AsyncResult) -> None:
        self._miracast_scanning = False
        try:
            _ok, stdout, _stderr = proc.communicate_utf8_finish(result)
            targets = json.loads(stdout) if stdout else []
            if isinstance(targets, list):
                self._miracast_targets = targets
        except Exception:
            pass
        self._refresh()

    def _check_update(self) -> bool:
        try:
            proc = Gio.Subprocess.new(
                [CLI, "check-update", "--json"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
            )
            proc.communicate_utf8_async(None, None, self._on_update_info)
        except Exception:
            pass
        return GLib.SOURCE_CONTINUE

    def _on_update_info(self, proc: Gio.Subprocess, result: Gio.AsyncResult) -> None:
        try:
            _ok, stdout, _stderr = proc.communicate_utf8_finish(result)
            info = json.loads(stdout) if stdout else None
            if isinstance(info, dict):
                self._update_info = info
                self._refresh()
        except Exception:
            pass

    def _run_update(self) -> None:
        # Run inside a transient systemd scope so the update survives the
        # kast-tray.service restart that the installer performs mid-update.
        argv = ["systemd-run", "--user", "--scope", "--quiet", CLI, "update"]
        try:
            subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception:
            subprocess.Popen([CLI, "update"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    def _spawn(self, *args: str) -> None:
        try:
            subprocess.Popen(
                [CLI, *args],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        finally:
            GLib.timeout_add_seconds(1, self._refresh_once)

    def _refresh_once(self) -> bool:
        self._refresh()
        return GLib.SOURCE_REMOVE

    def _status(self) -> dict:
        try:
            completed = subprocess.run(
                [CLI, "status", "--json"],
                capture_output=True,
                text=True,
                check=True,
            )
            return json.loads(completed.stdout)
        except Exception as exc:
            return {
                "error": str(exc),
                "receiver": {"active": False, "enabled": False, "installed": False, "name": "Kast Receiver"},
                "outbound": {"display_cast_installed": False, "airplay_sink_count": 0, "sinks": []},
                "mirror_mode": "mirror",
            }

    def _refresh(self) -> None:
        status = self._status()
        airplay_sinks = [sink for sink in status.get("outbound", {}).get("sinks", []) if sink.get("raop")]
        receiver = status.get("receiver", {})
        receiver_active = bool(receiver.get("active"))
        receiver_label = "on" if receiver_active else "off"
        icon = ICON_ACTIVE if receiver_active or airplay_sinks else ICON_IDLE

        self.indicator.set_icon_full(icon, "Kast")
        self.indicator.set_label(f"RX {receiver_label} | AP {len(airplay_sinks)}", "")

        menu = Gtk.Menu()

        header = Gtk.MenuItem(label=f"Receiver {receiver_label} | AirPlay outputs {len(airplay_sinks)}")
        header.set_sensitive(False)
        menu.append(header)

        mode_line = Gtk.MenuItem(label=f"Receiver mode: {status.get('mirror_mode', 'mirror')}")
        mode_line.set_sensitive(False)
        menu.append(mode_line)

        menu.append(Gtk.SeparatorMenuItem())

        item = Gtk.MenuItem(label="Display Cast...")
        item.connect("activate", lambda *_args: self._spawn("open-display-cast"))
        menu.append(item)

        item = Gtk.MenuItem(label="Display Cast — Miracast (drops Wi-Fi)...")
        item.connect("activate", lambda *_args: self._spawn("open-display-cast", "--drop-wifi"))
        menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        cast_header = Gtk.MenuItem(label=f"Chromecast Targets ({len(self._cast_targets)})")
        cast_header.set_sensitive(False)
        menu.append(cast_header)

        if self._cast_targets:
            for target in self._cast_targets:
                name = target.get("name") or target.get("address") or "Unknown device"
                target_item = Gtk.MenuItem(label=name)
                # gnome-network-displays owns the screencast pipeline and exposes
                # no connect API, so selecting a target opens its picker.
                target_item.connect("activate", lambda *_args: self._spawn("open-display-cast"))
                menu.append(target_item)
        else:
            none = Gtk.MenuItem(label="No cast targets found")
            none.set_sensitive(False)
            menu.append(none)

        rescan = Gtk.MenuItem(label="Rescan Chromecast Targets")
        rescan.connect("activate", lambda *_args: self._discover_cast_targets())
        menu.append(rescan)

        miracast_header = Gtk.MenuItem(label=f"Miracast Displays ({len(self._miracast_targets)})")
        miracast_header.set_sensitive(False)
        menu.append(miracast_header)

        for target in self._miracast_targets:
            name = target.get("name") or target.get("hwaddr") or "Unknown display"
            mc_item = Gtk.MenuItem(label=name)
            # Miracast needs the Wi-Fi radio; gnome-network-displays forms the
            # P2P group and runs the stream, so we hand off and drop Wi-Fi.
            mc_item.connect("activate", lambda *_args: self._spawn("open-display-cast", "--drop-wifi"))
            menu.append(mc_item)

        if self._miracast_scanning:
            scan_item = Gtk.MenuItem(label="Scanning for Miracast displays…")
            scan_item.set_sensitive(False)
        else:
            scan_item = Gtk.MenuItem(label="Scan for Miracast displays")
            scan_item.connect("activate", lambda *_args: self._scan_miracast())
        menu.append(scan_item)

        menu.append(Gtk.SeparatorMenuItem())

        item = Gtk.MenuItem(label="Sound Settings...")
        item.connect("activate", lambda *_args: self._spawn("open-sound"))
        menu.append(item)

        item = Gtk.MenuItem(label="Use Local Speakers")
        item.connect("activate", lambda *_args: self._spawn("select-local"))
        menu.append(item)

        item = Gtk.MenuItem(label="Reconnect Wi-Fi")
        item.connect("activate", lambda *_args: self._spawn("reconnect-wifi"))
        menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        airplay_header = Gtk.MenuItem(label="AirPlay Outputs")
        airplay_header.set_sensitive(False)
        menu.append(airplay_header)

        if airplay_sinks:
            for sink in airplay_sinks:
                label = sink["name"]
                if sink.get("default"):
                    label = f"* {label}"
                sink_item = Gtk.MenuItem(label=label)
                sink_item.connect("activate", lambda *_args, sink_id=sink["id"]: self._spawn("select-sink", str(sink_id)))
                menu.append(sink_item)
        else:
            none = Gtk.MenuItem(label="No AirPlay outputs discovered")
            none.set_sensitive(False)
            menu.append(none)

        menu.append(Gtk.SeparatorMenuItem())

        receiver_action = "Stop Receiver" if receiver_active else "Start Receiver"
        receiver_cmd = "receiver-stop" if receiver_active else "receiver-start"
        item = Gtk.MenuItem(label=receiver_action)
        item.connect("activate", lambda *_args, cmd=receiver_cmd: self._spawn(cmd))
        menu.append(item)

        item = Gtk.MenuItem(label="Restart Receiver")
        item.connect("activate", lambda *_args: self._spawn("receiver-restart"))
        menu.append(item)

        mode = status.get("mirror_mode", "mirror")
        mirror_mode_item = Gtk.RadioMenuItem(label="Mode: Mirror")
        overlay_mode_item = Gtk.RadioMenuItem(label="Mode: Video Overlay")
        overlay_mode_item.join_group(mirror_mode_item)
        (mirror_mode_item if mode == "mirror" else overlay_mode_item).set_active(True)
        # Connect AFTER set_active so the programmatic selection above doesn't
        # fire a spurious set-mode (which would restart the receiver).
        mirror_mode_item.connect("toggled", lambda w: self._spawn("set-mode", "mirror") if w.get_active() else None)
        overlay_mode_item.connect("toggled", lambda w: self._spawn("set-mode", "video-overlay") if w.get_active() else None)
        menu.append(mirror_mode_item)
        menu.append(overlay_mode_item)

        menu.append(Gtk.SeparatorMenuItem())

        if self._update_info and self._update_info.get("update_available"):
            update_item = Gtk.MenuItem(label=f"⬆ Update to v{self._update_info.get('latest')}")
            update_item.connect("activate", lambda *_args: self._run_update())
            menu.append(update_item)

        refresh = Gtk.MenuItem(label="Refresh")
        refresh.connect("activate", lambda *_args: self._refresh())
        menu.append(refresh)

        version_item = Gtk.MenuItem(label=f"kast v{status.get('version', '?')}")
        version_item.set_sensitive(False)
        menu.append(version_item)

        quit_item = Gtk.MenuItem(label="Quit Tray")
        quit_item.connect("activate", lambda *_args: Gtk.main_quit())
        menu.append(quit_item)

        menu.show_all()
        self.indicator.set_menu(menu)


def main() -> int:
    KastCastTray()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
