/*-
 * Copyright (c) 2017 elementary LLC. (https://elementary.io)
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

namespace ButMail {
    public class EnvelopeDragIcon {
        public static Gdk.Paintable create () {
            var snapshot = new Gtk.Snapshot ();
            var cr = snapshot.append_cairo (Graphene.Rect () { origin = { 0, 0 }, size = { 36, 28 } });
            cr.set_line_width (1);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.arc (31, 7, 2, -Math.PI / 2, 0);
            cr.arc (31, 23, 2, 0, Math.PI / 2);
            cr.arc (5, 23, 2, Math.PI / 2, Math.PI);
            cr.arc (5, 7, 2, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
            var paper = new Cairo.Pattern.linear (0, 5, 0, 25);
            paper.add_color_stop_rgb (0, 0.99, 0.99, 0.99);
            paper.add_color_stop_rgb (1, 0.85, 0.86, 0.87);
            cr.set_source (paper);
            cr.fill_preserve ();
            cr.set_source_rgb (0.55, 0.56, 0.57);
            cr.stroke ();
            cr.move_to (4, 24);
            cr.line_to (15, 14);
            cr.move_to (32, 24);
            cr.line_to (21, 14);
            cr.set_source_rgba (0.45, 0.46, 0.47, 0.6);
            cr.stroke ();
            cr.move_to (4, 6);
            cr.line_to (16, 16);
            cr.curve_to (17, 17, 19, 17, 20, 16);
            cr.line_to (32, 6);
            var flap = new Cairo.Pattern.linear (0, 6, 0, 17);
            flap.add_color_stop_rgb (0, 1, 1, 1);
            flap.add_color_stop_rgb (1, 0.93, 0.94, 0.95);
            cr.set_source (flap);
            cr.fill_preserve ();
            cr.set_source_rgb (0.6, 0.61, 0.62);
            cr.stroke ();
            return snapshot.free_to_paintable (Graphene.Size () { width = 36, height = 28 });
        }
    }
}
