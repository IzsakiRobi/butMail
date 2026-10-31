/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.RecipientEntry : Gtk.Entry {
    private RecipientStore store;
    private Gtk.Popover popup;
    private Gtk.ListBox list;
    private GenericArray<Recipient> matches = new GenericArray<Recipient> ();
    private ulong store_handler;
    private uint delay;
    private bool accepting;

    public RecipientEntry () {
        Object (hexpand: true, input_purpose: Gtk.InputPurpose.EMAIL);
        store = RecipientStore.get_default ();
        list = new Gtk.ListBox () { selection_mode = SINGLE, can_focus = false };
        list.row_activated.connect ((row) => accept (row.get_index ()));
        var scroller = new Gtk.ScrolledWindow (null, null) {
            hscrollbar_policy = NEVER, propagate_natural_height = true,
            max_content_height = 300, can_focus = false,
            margin_top = 8, margin_bottom = 8
        };
        scroller.add (list);
        popup = new Gtk.Popover (this) { modal = false, position = BOTTOM };
        popup.add (scroller);
        scroller.show_all ();
        changed.connect (queue_search);
        notify["cursor-position"].connect (queue_search);
        weak RecipientEntry self = this;
        store_handler = store.changed.connect (() => { if (self != null) { self.queue_search (); } });
        focus_in_event.connect (() => { queue_search (); return false; });
        focus_out_event.connect (() => { dismiss (); return false; });
        destroy.connect (() => {
            dismiss ();
            store.disconnect (store_handler);
            popup.destroy ();
        });
        ContactManager.get_default ();
    }

    public override bool key_press_event (Gdk.EventKey event) {
        if (!popup.visible) { return base.key_press_event (event); }
        uint key = event.keyval;
        if (key == Gdk.Key.Escape) { dismiss (); return true; }
        var selected = list.get_selected_row ();
        int position = selected != null ? selected.get_index () : -1;
        if (key == Gdk.Key.Down || key == Gdk.Key.Up) {
            int next = key == Gdk.Key.Down ? int.min (position + 1, (int) matches.length - 1) : int.max (position - 1, 0);
            list.select_row (list.get_row_at_index (next));
            return true;
        }
        if (key == Gdk.Key.Tab || key == Gdk.Key.ISO_Left_Tab) {
            if (key == Gdk.Key.Tab && (event.state & Gtk.accelerator_get_default_mod_mask ()) == 0 && position >= 0) {
                accept (position);
            } else { dismiss (); }
            return base.key_press_event (event);
        }
        if (position >= 0 && (key == Gdk.Key.Return || key == Gdk.Key.KP_Enter)) {
            accept (position);
            return true;
        }
        return base.key_press_event (event);
    }

    private void dismiss () {
        if (delay != 0) { Source.remove (delay); delay = 0; }
        popup.popdown ();
    }

    private void queue_search () {
        if (accepting) { return; }
        if (delay != 0) { Source.remove (delay); delay = 0; }
        if (!has_focus) { popup.popdown (); return; }
        delay = Timeout.add (120, () => { delay = 0; show_matches (); return Source.REMOVE; });
    }

    private void show_matches () {
        if (!has_focus || !get_mapped ()) { popup.popdown (); return; }
        int start, end;
        RecipientToken.bounds (text, get_position (), out start, out end);
        string query = text.substring (start, end - start).strip ();
        if (query.char_count () < 2 || query.has_suffix (">")) { popup.popdown (); return; }
        var entered = new Gee.HashSet<string> ();
        var addresses = new Camel.InternetAddress ();
        addresses.decode (text.substring (0, start) + text.substring (end));
        for (int i = 0; i < addresses.length (); i++) {
            unowned string? name, email;
            if (addresses.get (i, out name, out email) && email != null) { entered.add (email.casefold ()); }
        }
        foreach (var child in list.get_children ()) { child.destroy (); }
        matches = new GenericArray<Recipient> ();
        var suggestions = store.search (query);
        foreach (var item in suggestions.data) {
            if (entered.contains (item.email.casefold ())) { continue; }
            var content = new Gtk.Box (VERTICAL, 2) {
                margin_top = 6, margin_bottom = 6, margin_start = 10, margin_end = 10
            };
            if (item.name != "" && item.name != item.email) {
                content.add (new Gtk.Label (item.name) { xalign = 0, ellipsize = END, max_width_chars = 42 });
            }
            var address = new Gtk.Label (item.email) { xalign = 0, ellipsize = END, max_width_chars = 42 };
            address.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
            content.add (address);
            var row = new Gtk.ListBoxRow () { can_focus = false, focus_on_click = false, tooltip_text = item.formatted () };
            row.add (content);
            list.add (row);
            matches.add (item);
            if (matches.length == 8) { break; }
        }
        if (matches.length == 0) { popup.popdown (); return; }
        list.show_all ();
        list.select_row (list.get_row_at_index (0));
        var window = get_toplevel () as Gtk.Window;
        int available = window != null ? window.get_allocated_width () - 48 : 480;
        popup.width_request = int.max (240, int.min (get_allocated_width (), available));
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
        dismiss ();
        store.remember (recipient.name, recipient.email, 50, get_real_time () / 1000000);
    }
}
