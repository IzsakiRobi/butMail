/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class SplitResizeHandle : Gtk.Box {
        private SplitResizeHandle (Gtk.Widget pane, Gtk.Widget split, int minimum, int maximum) {
            Object (halign: Gtk.Align.END, width_request: 6, focusable: true,
                    tooltip_text: "Resize Column");
            set_cursor_from_name ("col-resize");
            double initial_width = 0;
            double initial_pointer = 0;
            var drag = new Gtk.GestureDrag ();
            drag.drag_begin.connect (() => {
                double y = 0;
                var pointer_event = drag.get_current_event ();
                if (pointer_event != null && pointer_event.get_position (out initial_pointer, out y)) {
                    initial_width = pane.get_width ();
                }
            });
            drag.drag_update.connect (() => {
                double x = 0, y = 0;
                var pointer_event = drag.get_current_event ();
                if (pointer_event != null && pointer_event.get_position (out x, out y)) {
                    resize (split, (int) (initial_width + x - initial_pointer), minimum, maximum);
                }
            });
            add_controller (drag);
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((key, code, modifiers) => {
                int step;
                switch (key) {
                    case Gdk.Key.Left: step = -16; break;
                    case Gdk.Key.Right: step = 16; break;
                    default: return false;
                }
                resize (split, pane.get_width () + step, minimum, maximum);
                return true;
            });
            add_controller (keys);
            split.bind_property ("collapsed", this, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
        }

        public static Gtk.Overlay wrap (Gtk.Widget pane, Gtk.Widget split, int minimum, int maximum) {
            var overlay = new Gtk.Overlay () { child = pane };
            var separator = new Gtk.Separator (Gtk.Orientation.VERTICAL) { halign = Gtk.Align.END, can_target = false };
            split.bind_property ("collapsed", separator, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
            overlay.add_overlay (separator);
            overlay.add_overlay (new SplitResizeHandle (pane, split, minimum, maximum));
            return overlay;
        }

        private void resize (Gtk.Widget split, int width, int minimum, int maximum) {
            int total = split.get_width ();
            if (total > 0) {
                int clamped = int.max (minimum, int.min (width, maximum));
                split.set ("sidebar-width-fraction", clamped / (double) total);
            }
        }
    }
}
