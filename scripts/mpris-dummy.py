#!/usr/bin/env python3
"""A silent MPRIS player, for verifying the media service without playing audio.

    python3 scripts/mpris-dummy.py [--name NAME] [--title T] [--artist A]
                                   [--length SECONDS] [--paused] [--no-art]

Publishes org.mpris.MediaPlayer2.<name> on the session bus with metadata, a
position that advances in real time, and working transport methods. Run two
copies with different --name values to exercise player selection.

It makes no sound and touches no audio device. Ctrl-C to stop.
"""

import argparse
import sys
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

MPRIS = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"
PATH = "/org/mpris/MediaPlayer2"


class DummyPlayer(dbus.service.Object):
    def __init__(self, bus, args):
        super().__init__(bus, PATH)
        self.args = args
        self.playing = not args.paused
        self.position = 0.0                 # seconds
        self.started = time.monotonic()
        self.track = 1

    # ── state ────────────────────────────────────────────────────────────

    def elapsed(self):
        if not self.playing:
            return self.position
        return self.position + (time.monotonic() - self.started)

    def metadata(self):
        data = {
            "mpris:trackid": dbus.ObjectPath(f"/org/bioma/track/{self.track}"),
            "mpris:length": dbus.Int64(int(self.args.length * 1_000_000)),
            "xesam:title": f"{self.args.title} {self.track}",
            "xesam:artist": dbus.Array([self.args.artist], signature="s"),
            "xesam:album": self.args.album,
            "xesam:albumArtist": dbus.Array([self.args.artist], signature="s"),
        }
        if not self.args.no_art:
            data["mpris:artUrl"] = self.args.art
        return dbus.Dictionary(data, signature="sv")

    def changed(self, properties):
        self.PropertiesChanged(PLAYER, dbus.Dictionary(properties, signature="sv"), [])

    # ── org.freedesktop.DBus.Properties ──────────────────────────────────

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self.GetAll(interface).get(prop, "")

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface == MPRIS:
            return dbus.Dictionary({
                "CanQuit": True,
                "CanRaise": False,
                "HasTrackList": False,
                "Identity": self.args.identity,
                "DesktopEntry": "bioma-dummy",
                "SupportedUriSchemes": dbus.Array([], signature="s"),
                "SupportedMimeTypes": dbus.Array([], signature="s"),
            }, signature="sv")
        if interface == PLAYER:
            return dbus.Dictionary({
                "PlaybackStatus": "Playing" if self.playing else "Paused",
                "LoopStatus": "None",
                "Rate": 1.0,
                "MinimumRate": 1.0,
                "MaximumRate": 1.0,
                "Shuffle": False,
                "Metadata": self.metadata(),
                "Volume": 1.0,
                "Position": dbus.Int64(int(self.elapsed() * 1_000_000)),
                "CanGoNext": True,
                "CanGoPrevious": True,
                "CanPlay": True,
                "CanPause": True,
                "CanSeek": True,
                "CanControl": True,
            }, signature="sv")
        return dbus.Dictionary({}, signature="sv")

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, interface, prop, value):
        pass

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    # ── org.mpris.MediaPlayer2 ───────────────────────────────────────────

    @dbus.service.method(MPRIS)
    def Raise(self):
        pass

    @dbus.service.method(MPRIS)
    def Quit(self):
        loop.quit()

    # ── org.mpris.MediaPlayer2.Player ────────────────────────────────────

    @dbus.service.method(PLAYER)
    def PlayPause(self):
        if self.playing:
            self.position = self.elapsed()
            self.playing = False
        else:
            self.started = time.monotonic()
            self.playing = True
        print(f"  <- PlayPause  now {'Playing' if self.playing else 'Paused'}", flush=True)
        self.changed({"PlaybackStatus": "Playing" if self.playing else "Paused"})

    @dbus.service.method(PLAYER)
    def Play(self):
        if not self.playing:
            self.PlayPause()

    @dbus.service.method(PLAYER)
    def Pause(self):
        if self.playing:
            self.PlayPause()

    @dbus.service.method(PLAYER)
    def Stop(self):
        self.position = 0.0
        self.playing = False
        self.changed({"PlaybackStatus": "Stopped"})

    @dbus.service.method(PLAYER)
    def Next(self):
        self.track += 1
        self.position = 0.0
        self.started = time.monotonic()
        print(f"  <- Next  track {self.track}", flush=True)
        self.changed({"Metadata": self.metadata()})

    @dbus.service.method(PLAYER)
    def Previous(self):
        self.track = max(1, self.track - 1)
        self.position = 0.0
        self.started = time.monotonic()
        print(f"  <- Previous  track {self.track}", flush=True)
        self.changed({"Metadata": self.metadata()})

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        self.position = max(0.0, self.elapsed() + offset / 1_000_000)
        self.started = time.monotonic()
        print(f"  <- Seek  {offset / 1_000_000:+.0f}s -> {self.position:.0f}s", flush=True)
        self.Seeked(dbus.Int64(int(self.position * 1_000_000)))

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track_id, position):
        self.position = max(0.0, position / 1_000_000)
        self.started = time.monotonic()
        self.Seeked(dbus.Int64(int(self.position * 1_000_000)))

    @dbus.service.signal(PLAYER, signature="x")
    def Seeked(self, position):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", default="biomadummy", help="bus name suffix")
    parser.add_argument("--identity", default="Bioma Dummy Player")
    parser.add_argument("--title", default="Silent Track")
    parser.add_argument("--artist", default="Nobody")
    parser.add_argument("--album", default="Nothing At All")
    parser.add_argument("--length", type=float, default=214.0, help="seconds")
    parser.add_argument("--art", default="file:///usr/share/pixmaps/archlinux-logo.png")
    parser.add_argument("--no-art", action="store_true")
    parser.add_argument("--paused", action="store_true")
    args = parser.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(f"{MPRIS}.{args.name}", bus)
    player = DummyPlayer(bus, args)

    print(f"{MPRIS}.{args.name} — {args.identity}", flush=True)
    print(f"  {args.title} / {args.artist}  ({args.length:.0f}s)"
          f"  {'Playing' if player.playing else 'Paused'}", flush=True)

    global loop
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
