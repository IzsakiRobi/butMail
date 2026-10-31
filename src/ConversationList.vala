/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class ConversationRow : Gtk.Box {
        private Settings settings;
        private Conversation? bound_conversation;
        private ulong flags_handler;
        private ulong messages_handler;
        private Gtk.Label sender_label;
        private Gtk.Box unread_dot;
        private Gtk.Image star_icon;
        private Gtk.Label message_count;

        public ConversationRow (Settings settings) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
            add_css_class ("conversation-row");
            this.settings = settings;
        }

        public void bind_conversation (Conversation conversation) {
            unbind_conversation ();
            bound_conversation = conversation;
            while (get_first_child () != null) { remove (get_first_child ()); }
            var latest = conversation.messages.get_n_items () > 0
                ? (Message) conversation.messages.get_item (conversation.messages.get_n_items () - 1) : null;
            var avatar = new SenderAvatar (conversation.sender, latest != null ? latest.address : "");
            var avatar_overlay = new Gtk.Overlay () { child = avatar, valign = Gtk.Align.START };
            settings.bind ("show-avatars", avatar_overlay, "visible", SettingsBindFlags.GET);
            unread_dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                halign = Gtk.Align.END, valign = Gtk.Align.START, margin_top = 1, margin_end = 1, can_target = false
            };
            unread_dot.add_css_class ("unread-dot");
            avatar_overlay.add_overlay (unread_dot);
            star_icon = new Gtk.Image.from_icon_name ("starred-symbolic") {
                pixel_size = 14, halign = Gtk.Align.END, valign = Gtk.Align.END, margin_bottom = 1, margin_end = 1, can_target = false
            };
            star_icon.add_css_class ("conversation-star");
            avatar_overlay.add_overlay (star_icon);
            append (avatar_overlay);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) { hexpand = true };
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            sender_label = line (conversation.sender);
            sender_label.hexpand = true;
            heading.append (sender_label);
            var time = new Gtk.Label (conversation.time_label);
            time.add_css_class ("caption");
            time.add_css_class ("dim-label");
            heading.append (time);
            text.append (heading);
            var subject_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var subject = line (conversation.subject);
            subject.hexpand = true;
            subject_row.append (subject);
            message_count = new Gtk.Label (null) { valign = Gtk.Align.CENTER };
            message_count.add_css_class ("conversation-count");
            subject_row.append (message_count);
            text.append (subject_row);
            var preview = line (conversation.preview);
            preview.add_css_class ("dim-label");
            text.append (preview);
            append (text);
            update_flags ();
            flags_handler = conversation.notify.connect (update_flags);
            messages_handler = conversation.messages.items_changed.connect (update_flags);
        }

        public void unbind_conversation () {
            if (bound_conversation != null) {
                if (flags_handler != 0) { bound_conversation.disconnect (flags_handler); flags_handler = 0; }
                if (messages_handler != 0) { bound_conversation.messages.disconnect (messages_handler); messages_handler = 0; }
            }
            bound_conversation = null;
        }

        private void update_flags () {
            if (bound_conversation.unread) { sender_label.add_css_class ("heading"); }
            else { sender_label.remove_css_class ("heading"); }
            unread_dot.visible = bound_conversation.unread;
            star_icon.visible = bound_conversation.starred;
            uint count = bound_conversation.messages.get_n_items ();
            message_count.label = count.to_string ();
            message_count.visible = count > 1;
            message_count.tooltip_text = "%u messages".printf (count);
        }

        private Gtk.Label line (string text) {
            return new Gtk.Label (text) { xalign = 0, ellipsize = Pango.EllipsizeMode.END };
        }
    }

    public class ConversationList : Gtk.Box {
        public bool has_messages { get; private set; }
        public signal void conversation_selected (Conversation? conversation);
        public signal void conversation_activated ();
        private ListStore visible_items;
        private Gtk.MultiSelection selection;
        private Gtk.Stack stack;
        private EmptyState empty;
        private Gtk.SearchEntry search;
        private Gtk.Button empty_trash;
        private Folder? folder;
        private ulong folder_handler;
        private ulong status_handler;
        private bool filtering;
        private Gtk.PopoverMenu? context_menu;

        public ConversationList (Settings settings) {
            Object (orientation: Gtk.Orientation.VERTICAL);
            search = new Gtk.SearchEntry () {
                placeholder_text = "Search messages", margin_start = 12, margin_end = 12,
                margin_top = 8, margin_bottom = 12
            };
            search.search_changed.connect (() => refilter ());
            append (search);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            empty_trash = new Gtk.Button () {
                action_name = "win.empty-trash", visible = false,
                margin_start = 12, margin_end = 12, margin_top = 12, margin_bottom = 12, height_request = 36
            };
            empty_trash.add_css_class ("trash-action");
            var trash_content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { halign = Gtk.Align.CENTER };
            trash_content.append (new Gtk.Image.from_icon_name ("user-trash-symbolic"));
            trash_content.append (new Gtk.Label ("Empty Trash…"));
            empty_trash.child = trash_content;
            append (empty_trash);
            visible_items = new ListStore (typeof (Conversation));
            selection = new Gtk.MultiSelection (visible_items);
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((item) => {
                var list_item = (Gtk.ListItem) item;
                var row = new ConversationRow (settings);
                var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
                click.released.connect ((presses, x, y) => {
                    if (presses == 1 && list_item.position != Gtk.INVALID_LIST_POSITION) {
                        conversation_activated ();
                    }
                });
                row.add_controller (click);
                var context = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
                context.pressed.connect ((presses, x, y) => {
                    if (list_item.position == Gtk.INVALID_LIST_POSITION) { return; }
                    context.set_state (Gtk.EventSequenceState.CLAIMED);
                    if (!selection.is_selected (list_item.position)) { selection.select_item (list_item.position, true); }
                    show_menu (row, x, y);
                });
                row.add_controller (context);
                Conversation[] pressed_selection = {};
                var press = new Gtk.GestureClick () {
                    button = Gdk.BUTTON_PRIMARY, propagation_phase = Gtk.PropagationPhase.CAPTURE
                };
                press.pressed.connect (() => {
                    pressed_selection = selection.is_selected (list_item.position) ? get_selected_conversations () : new Conversation[0];
                });
                row.add_controller (press);
                var drag = new Gtk.DragSource () { actions = Gdk.DragAction.MOVE, button = Gdk.BUTTON_PRIMARY };
                drag.prepare.connect (() => {
                    if (folder == null || !folder.writable || folder.role == FolderRole.STARRED || list_item.position == Gtk.INVALID_LIST_POSITION) {
                        return null;
                    }
                    if (!selection.is_selected (list_item.position)) {
                        selection.select_item (list_item.position, true);
                    }
                    if (pressed_selection.length > 1) {
                        foreach (var selected in pressed_selection) {
                            uint position;
                            if (visible_items.find (selected, out position)) { selection.select_item (position, false); }
                        }
                    }
                    var payload = new ConversationDrag (folder, get_selected_conversations ());
                    var value = Value (typeof (ConversationDrag));
                    value.set_object (payload);
                    drag.set_icon (EnvelopeDragIcon.create (), 4, 4);
                    return new Gdk.ContentProvider.for_value (value);
                });
                drag.drag_end.connect (() => { pressed_selection = {}; });
                row.add_controller (drag);
                list_item.child = row;
            });
            factory.bind.connect ((item) => {
                var list_item = (Gtk.ListItem) item;
                ((ConversationRow) list_item.child).bind_conversation ((Conversation) list_item.item);
            });
            factory.unbind.connect ((item) => {
                ((ConversationRow) ((Gtk.ListItem) item).child).unbind_conversation ();
            });
            var list = new Gtk.ListView (selection, factory) { single_click_activate = false };
            list.add_css_class ("conversation-list");
            list.add_css_class ("separators");
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((key, code, modifiers) => {
                if (selection.get_selection ().is_empty ()) { return false; }
                if ((key == Gdk.Key.Delete || key == Gdk.Key.KP_Delete) &&
                    (modifiers & Gtk.accelerator_get_default_mod_mask ()) == 0) {
                    var actions = get_root () as ActionGroup;
                    if (actions != null && actions.get_action_enabled ("trash")) {
                        var selected = selection.get_selection ();
                        uint next = selected.get_minimum ();
                        while (next < visible_items.get_n_items () && selected.contains (next)) { next++; }
                        if (next == visible_items.get_n_items ()) {
                            next = selected.get_minimum ();
                            while (next > 0 && selected.contains (next)) { next--; }
                        }
                        if (!selected.contains (next)) {
                            var scroll = new Gtk.ScrollInfo ();
                            scroll.set_enable_horizontal (false);
                            scroll.set_enable_vertical (false);
                            list.scroll_to (next, Gtk.ListScrollFlags.FOCUS, (owned) scroll);
                        }
                    }
                    return list.activate_action_variant ("win.trash", null);
                }
                if (key != Gdk.Key.Menu && !(key == Gdk.Key.F10 && (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0)) { return false; }
                show_menu (list, 24, 24);
                return true;
            });
            list.add_controller (keys);
            list.activate.connect (() => { conversation_activated (); });
            selection.selection_changed.connect (() => {
                if (!filtering) { notify_selection (); }
            });
            stack = new Gtk.Stack () { vexpand = true };
            stack.add_named (new Gtk.ScrolledWindow () {
                child = list, hscrollbar_policy = Gtk.PolicyType.NEVER
            }, "list");
            empty = new EmptyState () { icon_name = "mail-read-symbolic" };
            stack.add_named (empty, "empty");
            append (stack);
        }

        public void show_status (string title, string description) {
            search.sensitive = false;
            empty.icon_name = "preferences-system-time-symbolic";
            empty.title = title;
            empty.description = description;
            stack.visible_child_name = "empty";
        }

        public void show_folder (Folder selected_folder) {
            close_menu ();
            search.sensitive = selected_folder.selectable;
            if (folder != null && folder_handler != 0) {
                folder.conversations.disconnect (folder_handler);
            }
            if (folder != null && status_handler != 0) { folder.disconnect (status_handler); }
            folder = selected_folder;
            empty_trash.visible = folder.role == FolderRole.TRASH;
            folder_handler = folder.conversations.items_changed.connect (() => refilter (true));
            status_handler = folder.notify.connect (() => { update_status (); });
            search.text = "";
            refilter ();
        }

        public void select_first () {
            if (visible_items.get_n_items () > 0) {
                selection.select_item (0, true);
            }
        }

        public bool select_message (string uid) {
            search.text = "";
            refilter ();
            for (uint i = 0; i < visible_items.get_n_items (); i++) {
                var conversation = (Conversation) visible_items.get_item (i);
                for (uint j = 0; j < conversation.messages.get_n_items (); j++) {
                    if (((Message) conversation.messages.get_item (j)).uid == uid) {
                        selection.select_item (i, true);
                        return true;
                    }
                }
            }
            return false;
        }

        public void refresh_selection () {
            notify_selection ();
        }

        public void clear_selection () {
            selection.unselect_all ();
        }

        private void show_menu (Gtk.Widget anchor, double x, double y) {
            close_menu ();
            var menu = new Menu ();
            menu.append ("Move to Trash", "win.trash");
            menu.append ("Mark as Read", "win.mark-read");
            menu.append ("Mark as Unread", "win.mark-unread");
            menu.append ("Star", "win.mark::star");
            menu.append ("Unstar", "win.mark::unstar");
            Graphene.Point position;
            if (!anchor.compute_point (this, Graphene.Point () { x = (float) x, y = (float) y }, out position)) { return; }
            var popover = new Gtk.PopoverMenu.from_model (menu);
            popover.insert_action_group ("win", get_root () as ActionGroup);
            popover.set_parent (this);
            popover.pointing_to = Gdk.Rectangle () { x = (int) position.x, y = (int) position.y, width = 1, height = 1 };
            context_menu = popover;
            popover.popup ();
        }

        private void close_menu () {
            if (context_menu != null) {
                var popover = context_menu;
                context_menu = null;
                popover.popdown ();
                popover.unparent ();
            }
        }

        protected override void dispose () {
            close_menu ();
            if (folder != null && status_handler != 0) { folder.disconnect (status_handler); status_handler = 0; }
            if (folder != null && folder_handler != 0) {
                folder.conversations.disconnect (folder_handler);
                folder_handler = 0;
            }
            base.dispose ();
        }

        public Conversation[] get_selected_conversations () {
            var result = new GenericArray<Conversation> ();
            for (uint i = 0; i < visible_items.get_n_items (); i++) {
                if (selection.is_selected (i)) { result.add ((Conversation) visible_items.get_item (i)); }
            }
            return result.data;
        }

        private void notify_selection () {
            var selected = get_selected_conversations ();
            conversation_selected (selected.length == 1 ? selected[0] : null);
        }

        private void refilter (bool select_next = false) {
            close_menu ();
            var previous = get_selected_conversations ();
            uint selected_position = selection.get_selection ().get_minimum ();
            var next = new GenericArray<Conversation> ();
            if (folder != null) {
                for (uint i = 0; i < folder.conversations.get_n_items (); i++) {
                    var conversation = (Conversation) folder.conversations.get_item (i);
                    if (conversation.matches (search.text.strip ())) { next.add (conversation); }
                }
            }
            uint count = visible_items.get_n_items ();
            uint start = 0, suffix = 0;
            while (start < count && start < next.length && visible_items.get_item (start) == next[start]) { start++; }
            while (suffix < count - start && suffix < next.length - start &&
                visible_items.get_item (count - suffix - 1) == next[next.length - suffix - 1]) { suffix++; }
            filtering = true;
            if (start + suffix != count || start + suffix != next.length) {
                var changed = new GenericArray<Conversation> ();
                for (uint i = start; i < next.length - suffix; i++) { changed.add (next[i]); }
                visible_items.splice (start, count - start - suffix, changed.data);
            }
            bool retained = false;
            foreach (var conversation in previous) {
                uint position;
                if (visible_items.find (conversation, out position)) {
                    selection.select_item (position, false);
                    retained = true;
                }
            }
            if (select_next && previous.length > 0 && !retained && next.length > 0) {
                selection.select_item (uint.min (selected_position, next.length - 1), true);
            }
            filtering = false;
            update_status ();
            notify_selection ();
        }

        private void update_status () {
            bool no_results = search.text.strip () != "";
            empty.icon_name = folder != null && folder.loading ? "preferences-system-time-symbolic" :
                no_results ? "edit-find-symbolic" : "mail-read-symbolic";
            empty.title = folder != null && folder.loading ? "Loading Messages…" :
                folder != null && folder.error_message != null ? "Unable to Load Messages" : no_results ? "No Results" : "No Messages";
            empty.description = folder != null ? folder.error_message ?? "" : "";
            has_messages = visible_items.get_n_items () > 0;
            stack.visible_child_name = has_messages ? "list" : "empty";
        }
    }
}
