/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    public class LoadingIndicator : Gtk.Box {
        public LoadingIndicator () {
            Object (orientation: Gtk.Orientation.VERTICAL, halign: Gtk.Align.FILL,
                valign: Gtk.Align.FILL, vexpand: false, height_request: 160);
            add_css_class ("butmail-loading-surface");
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
                halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER, vexpand = true
            };
            content.add_css_class ("butmail-loading-indicator");
            content.append (new Adw.Spinner () { width_request = 20, height_request = 20 });
            content.append (new Gtk.Label ("Loading…"));
            append (content);
        }

    }
}
