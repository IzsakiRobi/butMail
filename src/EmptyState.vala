/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class EmptyState : Gtk.Box {
        private Gtk.Image icon;
        private Gtk.Label heading;
        private Gtk.Label details;

        public string icon_name {
            owned get { return icon.icon_name; }
            set { icon.icon_name = value; }
        }
        public string title {
            owned get { return heading.label; }
            set { heading.label = value; }
        }
        public string description {
            owned get { return details.label; }
            set { details.label = value; details.visible = value != ""; }
        }

        public EmptyState () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 18,
                halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
                margin_start: 16, margin_end: 16);
            add_css_class ("status-watermark");
            icon = new Gtk.Image () { pixel_size = 72 };
            heading = new Gtk.Label (null) { wrap = true, justify = Gtk.Justification.CENTER };
            details = new Gtk.Label (null) { wrap = true, justify = Gtk.Justification.CENTER, max_width_chars = 36, visible = false };
            append (icon);
            append (heading);
            append (details);
        }
    }
}
