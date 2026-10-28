/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    private class MessageHeader : Gtk.Box {
        public bool active { get; set; }

        public MessageHeader (bool expanded) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, hexpand: true, focusable: true,
                accessible_role: Gtk.AccessibleRole.BUTTON, tooltip_text: "Expand or Collapse Message");
            active = expanded;
            notify["active"].connect (update_expanded);
            update_expanded ();
            var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
            click.released.connect ((presses, x, y) => {
                for (var target = pick (x, y, Gtk.PickFlags.DEFAULT); target != null && target != this; target = target.parent) {
                    if (target is Gtk.Button) { return; }
                }
                grab_focus ();
                active = !active;
            });
            add_controller (click);
            var keyboard = new Gtk.EventControllerKey ();
            keyboard.key_pressed.connect ((key, code, modifiers) => {
                if (has_focus && (key == Gdk.Key.space || key == Gdk.Key.Return || key == Gdk.Key.KP_Enter)) {
                    active = !active;
                    return true;
                }
                return false;
            });
            add_controller (keyboard);
        }

        private void update_expanded () {
            update_state (Gtk.AccessibleState.EXPANDED, active, -1);
        }
    }

    public class MessageCard : Gtk.Box {
        public signal void body_requested (Message message);
        public signal void star_requested (Message message, bool starred);
        public signal void compose_requested (ComposeMode mode);
        public signal void address_copied ();

        public MessageCard (Message message, string subject, bool expanded) {
            Object (orientation: Gtk.Orientation.VERTICAL, vexpand: false);
            add_css_class ("card");
            add_css_class ("message-card");
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.add_css_class ("message-card-header");
            var toggle = new MessageHeader (expanded);
            toggle.add_css_class ("message-header");
            toggle.state_flags_changed.connect (() => {
                if ((toggle.get_state_flags () & Gtk.StateFlags.FOCUS_VISIBLE) != 0) {
                    header.add_css_class ("keyboard-focus");
                } else {
                    header.remove_css_class ("keyboard-focus");
                }
            });
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            var avatar = new SenderAvatar (message.sender, message.address) { valign = Gtk.Align.START };
            heading.append (avatar);
            var fields = new Gtk.Grid () { column_spacing = 8, row_spacing = 6, hexpand = true };
            add_field (fields, 0, "From:", address_value (message.sender, message.address));
            add_field (fields, 1, "To:", recipient_values (message.recipient));
            add_field (fields, 2, "Subject:", text_line (subject));
            var summary = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) { hexpand = true };
            if (message.sender != message.address) {
                var name = text_line (message.sender);
                name.hexpand = false;
                name.width_chars = 0;
                summary.append (name);
            }
            summary.append (address_line (message.address));
            var header_fields = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
            header_fields.append (summary);
            header_fields.append (fields);
            heading.append (header_fields);
            toggle.append (heading);
            header.append (toggle);

            var actions = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                valign = Gtk.Align.START, margin_top = 12, margin_end = 12
            };
            var date_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var date = new Gtk.Label (message.time_label);
            date.add_css_class ("dim-label");
            date.add_css_class ("caption");
            date_row.append (date);
            var star = new Gtk.ToggleButton () { tooltip_text = "Star Message", sensitive = !message.read_only };
            star.add_css_class ("flat");
            message.bind_property ("starred", star, "active", BindingFlags.SYNC_CREATE);
            star.icon_name = star.active ? "starred-symbolic" : "non-starred-symbolic";
            star.notify["active"].connect (() => { star.icon_name = star.active ? "starred-symbolic" : "non-starred-symbolic"; });
            star.clicked.connect (() => {
                bool active = star.active;
                star.active = message.starred;
                star_requested (message, active);
            });
            date_row.append (star);
            actions.append (date_row);
            var group = new SimpleActionGroup ();
            var reply = new SimpleAction ("reply", null);
            reply.activate.connect (() => { compose_requested (ComposeMode.REPLY); });
            group.add_action (reply);
            var reply_all = new SimpleAction ("reply-all", null);
            reply_all.activate.connect (() => { compose_requested (ComposeMode.REPLY_ALL); });
            group.add_action (reply_all);
            var forward = new SimpleAction ("forward", null);
            forward.activate.connect (() => { compose_requested (ComposeMode.FORWARD); });
            group.add_action (forward);
            insert_action_group ("message", group);
            var menu = new Menu ();
            menu.append ("Reply", "message.reply");
            menu.append ("Reply All", "message.reply-all");
            menu.append ("Forward", "message.forward");
            var more = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic", menu_model = menu, halign = Gtk.Align.END, tooltip_text = "More"
            };
            more.add_css_class ("flat");
            actions.append (more);
            header.append (actions);
            append (header);

            var message_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            message_content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            message_content.append (new MessageBody (message));
            var revealer = new Gtk.Revealer () {
                child = message_content, transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
                reveal_child = expanded
            };
            append (revealer);
            message.expanded = expanded;
            toggle.notify["active"].connect (() => {
                message.expanded = toggle.active;
                if (toggle.active && !message.loaded) { body_requested (message); }
                revealer.reveal_child = toggle.active;
                fields.visible = toggle.active;
                summary.visible = !toggle.active;
                more.visible = toggle.active;
                update_collapsed (toggle.active);
            });
            fields.visible = expanded;
            summary.visible = !expanded;
            more.visible = expanded;
            update_collapsed (expanded);
        }

        private void update_collapsed (bool expanded) {
            if (expanded) {
                remove_css_class ("collapsed");
            } else {
                add_css_class ("collapsed");
            }
        }

        private void add_field (Gtk.Grid grid, int row, string name, Gtk.Widget value) {
            var label = new Gtk.Label (name) { xalign = 1, valign = Gtk.Align.START };
            label.add_css_class ("dim-label");
            grid.attach (label, 0, row);
            grid.attach (value, 1, row);
        }

        private Gtk.Label text_line (string text) {
            return new Gtk.Label (text) {
                xalign = 0, ellipsize = Pango.EllipsizeMode.END, hexpand = true,
                width_chars = 12, max_width_chars = 40, tooltip_text = text
            };
        }

        /* ----- Address Details and Clipboard ----- */
        private Gtk.Widget address_value (string? name, string email) {
            var value = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true };
            if (name != null && name != "" && name != email) { value.append (text_line (name)); }
            value.append (address_line (email));
            return value;
        }

        private Gtk.Widget recipient_values (string recipients) {
            var parsed = new Camel.InternetAddress ();
            if (parsed.decode (recipients) <= 0) { return text_line (recipients); }
            var values = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) { hexpand = true };
            for (int i = 0; i < parsed.length (); i++) {
                unowned string? name, email;
                if (parsed.get (i, out name, out email) && email != null && email != "") {
                    values.append (address_value (name, email));
                }
            }
            return values;
        }

        private Gtk.Widget address_line (string email) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            row.add_css_class ("message-address-line");
            var label = text_line ("<" + email + ">");
            label.hexpand = false;
            label.width_chars = 0;
            label.add_css_class ("message-address");
            row.append (label);
            var copy = new Gtk.Button () {
                child = new Gtk.Image.from_icon_name ("edit-copy-symbolic") { pixel_size = 12 },
                tooltip_text = "Copy Email Address", valign = Gtk.Align.CENTER
            };
            copy.add_css_class ("flat");
            copy.add_css_class ("address-copy");
            copy.clicked.connect (() => {
                get_clipboard ().set_text (email);
                address_copied ();
            });
            row.append (copy);
            return row;
        }
    }
}
