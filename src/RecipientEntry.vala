/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    public class RecipientEntry : Gtk.Entry {
        private RecipientStore store;
        private Gtk.Popover popup;
        private Gtk.ListBox list;
        private Gtk.EventControllerFocus entry_focus;
        private GenericArray<Recipient> matches = new GenericArray<Recipient> ();
        private ulong store_handler;
        private uint delay;
        private bool accepting;

        public RecipientEntry (RecipientStore store) {
            Object (hexpand: true, input_purpose: Gtk.InputPurpose.EMAIL);
            this.store = store;
            list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.SINGLE, focusable = false };
            list.add_css_class ("navigation-sidebar");
            list.row_activated.connect ((row) => accept (row.get_index ()));
            popup = new Gtk.Popover () { autohide = false, has_arrow = false, focusable = false, position = Gtk.PositionType.BOTTOM };
            popup.child = new Gtk.ScrolledWindow () {
                child = list, hscrollbar_policy = Gtk.PolicyType.NEVER, propagate_natural_height = true,
                max_content_height = 320, focusable = false
            };
            popup.set_parent (this);
            changed.connect (queue_search);
            notify["cursor-position"].connect (queue_search);
            weak RecipientEntry self = this;
            store_handler = store.changed.connect (() => { if (self != null) { self.queue_search (); } });
            entry_focus = new Gtk.EventControllerFocus ();
            entry_focus.enter.connect (queue_search);
            entry_focus.leave.connect (() => popup.popdown ());
            add_controller (entry_focus);
            var keys = new Gtk.EventControllerKey () { propagation_phase = Gtk.PropagationPhase.CAPTURE };
            keys.key_pressed.connect ((key, code, modifiers) => {
                if (!popup.visible) { return false; }
                if (key == Gdk.Key.Escape) { popup.popdown (); return true; }
                var selected = list.get_selected_row ();
                int position = selected != null ? selected.get_index () : -1;
                if (key == Gdk.Key.Down || key == Gdk.Key.Up) {
                    int next = key == Gdk.Key.Down ? int.min (position + 1, (int) matches.length - 1) : int.max (position - 1, 0);
                    list.select_row (list.get_row_at_index (next));
                    return true;
                }
                if (position >= 0 && (key == Gdk.Key.Return || key == Gdk.Key.KP_Enter || key == Gdk.Key.Tab)) {
                    accept (position);
                    return true;
                }
                return false;
            });
            add_controller (keys);
        }

        /* ----- Recipient Suggestions ----- */
        private void queue_search () {
            if (accepting) { return; }
            if (delay != 0) { Source.remove (delay); delay = 0; }
            if (!entry_focus.contains_focus) { popup.popdown (); return; }
            delay = Timeout.add (120, () => { delay = 0; show_matches (); return Source.REMOVE; });
        }

        private void show_matches () {
            if (!entry_focus.contains_focus || !get_mapped ()) { popup.popdown (); return; }
            int start, end;
            RecipientToken.bounds (text, get_position (), out start, out end);
            string query = text.substring (start, end - start).strip ();
            if (query.char_count () < 2 || query.has_suffix (">")) { popup.popdown (); return; }
            var entered = new HashTable<string, bool> (str_hash, str_equal);
            var addresses = new Camel.InternetAddress ();
            addresses.decode (text.substring (0, start) + text.substring (end));
            for (int i = 0; i < addresses.length (); i++) {
                unowned string? name, email;
                if (addresses.get (i, out name, out email) && email != null) { entered.insert (email.casefold (), true); }
            }
            for (var child = list.get_first_child (); child != null; child = list.get_first_child ()) { list.remove (child); }
            matches = new GenericArray<Recipient> ();
            var suggestions = store.search (query);
            foreach (var item in suggestions.data) {
                if (entered.contains (item.email.casefold ())) { continue; }
                var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                    margin_top = 6, margin_bottom = 6, margin_start = 8, margin_end = 8
                };
                if (item.name != "") {
                    content.append (new Gtk.Label (item.name) {
                        xalign = 0, ellipsize = Pango.EllipsizeMode.END, width_chars = 24, max_width_chars = 60
                    });
                }
                var address = new Gtk.Label (item.email) {
                    xalign = 0, ellipsize = Pango.EllipsizeMode.END, width_chars = 24, max_width_chars = 60
                };
                address.add_css_class ("dim-label");
                address.add_css_class ("caption");
                content.append (address);
                list.append (new Gtk.ListBoxRow () { child = content, focusable = false, tooltip_text = item.formatted () });
                matches.add (item);
                if (matches.length == 8) { break; }
            }
            if (matches.length == 0) { popup.popdown (); return; }
            list.select_row (list.get_row_at_index (0));
            popup.width_request = int.max (280, get_width ());
            popup.popup ();
        }

        private void accept (int position) {
            if (position < 0 || position >= matches.length) { return; }
            int start, end;
            RecipientToken.bounds (text, get_position (), out start, out end);
            var recipient = matches[(uint) position];
            string prefix = text.substring (0, start) + recipient.formatted ();
            string suffix = text.substring (end);
            if (suffix == "") { prefix += ", "; }
            accepting = true;
            text = prefix + suffix;
            set_position ((int) prefix.char_count ());
            accepting = false;
            popup.popdown ();
            store.remember (recipient.name, recipient.email, 50, get_real_time () / 1000000);
        }

        protected override void dispose () {
            if (delay != 0) { Source.remove (delay); delay = 0; }
            if (store_handler != 0) { store.disconnect (store_handler); store_handler = 0; }
            if (popup.get_parent () != null) { popup.unparent (); }
            base.dispose ();
        }
    }
}
