#!/usr/bin/env python3
import sys
import os
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
import time

class ClockWidget(Gtk.Window):
    def __init__(self):
        super().__init__(title="HomeClockWidget")
        self.set_name("HomeClockWidget")
        self.set_decorated(False)
        self.set_app_paintable(True)
        self.set_default_size(320, 160)

        # Enable transparency/RGBA visual
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None and screen.is_composited():
            self.set_visual(visual)

        # EventBox to capture mouse events for dragging
        event_box = Gtk.EventBox()
        event_box.set_visible_window(False)  # Transparent event box
        self.add(event_box)

        # Layout inside event_box
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        vbox.set_valign(Gtk.Align.CENTER)
        vbox.set_halign(Gtk.Align.CENTER)
        event_box.add(vbox)

        self.time_label = Gtk.Label()
        self.time_label.get_style_context().add_class("time-label")
        vbox.pack_start(self.time_label, True, True, 0)

        self.date_label = Gtk.Label()
        self.date_label.get_style_context().add_class("date-label")
        vbox.pack_start(self.date_label, True, True, 0)

        # Styles
        self.apply_css()

        # Connect drag events to EventBox
        event_box.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        event_box.connect("button-press-event", self.on_button_press)

        # Update clock
        self.update_clock()
        GLib.timeout_add_seconds(1, self.update_clock)

        # Show all
        self.show_all()

    def on_button_press(self, widget, event):
        if event.button == 1:  # Left click drag
            # Explicitly cast coordinates to integer for the Wayland drag API
            self.begin_move_drag(event.button, int(event.x_root), int(event.y_root), event.time)
            return True
        return False

    def update_clock(self):
        self.time_label.set_text(time.strftime("%H:%M"))
        self.date_label.set_text(time.strftime("%A, %B %d"))
        return True

    def apply_css(self):
        css = b"""
        window {
            background-color: rgba(22, 22, 36, 0.55);
            border: 1px solid rgba(196, 167, 231, 0.20);
            border-radius: 20px;
        }
        .time-label {
            color: #e0def4;
            font-family: "JetBrainsMono Nerd Font", "Noto Sans", sans-serif;
            font-size: 54pt;
            font-weight: bold;
            margin-top: 10px;
        }
        .date-label {
            color: #c4a7e7;
            font-family: "JetBrainsMono Nerd Font", "Noto Sans", sans-serif;
            font-size: 14pt;
            font-weight: normal;
            margin-bottom: 10px;
            opacity: 0.85;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

if __name__ == "__main__":
    GLib.set_prgname("HomeClockWidget")
    GLib.set_application_name("HomeClockWidget")
    
    app = ClockWidget()
    Gtk.main()
