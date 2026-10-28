/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class MessageCard : Gtk.Box {
        public signal void body_requested (Message message);
        public signal void star_requested (Message message, bool starred);
        public signal void compose_requested (ComposeMode mode);

        public MessageCard (Message message, string subject, bool expanded) {
            Object (orientation: Gtk.Orientation.VERTICAL, vexpand: false);
            add_css_class ("card");
            add_css_class ("message-card");
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.add_css_class ("message-card-header");
            var toggle = new Gtk.ToggleButton () {
                active = expanded, hexpand = true, tooltip_text = "Expand or Collapse Message"
            };
            toggle.add_css_class ("flat");
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
            add_field (fields, 0, "From:", message.sender + "\n<" + message.address + ">");
            add_field (fields, 1, "To:", message.recipient.replace (" <", "\n<"));
            add_field (fields, 2, "Subject:", subject);
            var summary = new Gtk.Label (message.sender + " <" + message.address + ">") {
                xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END
            };
            var header_fields = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
            header_fields.append (summary);
            header_fields.append (fields);
            heading.append (header_fields);
            toggle.child = heading;
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
            toggle.toggled.connect (() => {
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

        private void add_field (Gtk.Grid grid, int row, string name, string value) {
            var label = new Gtk.Label (name) { xalign = 1, valign = Gtk.Align.START };
            label.add_css_class ("dim-label");
            grid.attach (label, 0, row);
            grid.attach (new Gtk.Label (value) {
                xalign = 0, ellipsize = Pango.EllipsizeMode.END, hexpand = true,
                width_chars = 12, max_width_chars = 40, tooltip_text = value
            }, 1, row);
        }
    }
}
