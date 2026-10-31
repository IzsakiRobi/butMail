/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class FolderRow : Gtk.Box {
        private weak FolderSidebar sidebar;
        private Folder? folder;
        private Gtk.TreeExpander expander;
        private Gtk.Label label;
        private Gtk.Label count;
        private Gtk.Image icon;
        private Gtk.Box insertion;
        private ulong changed_handler;
        private ulong children_handler;

        public FolderRow (FolderSidebar sidebar) {
            Object (orientation: Gtk.Orientation.VERTICAL);
            this.sidebar = sidebar;
            add_css_class ("folder-row");
            expander = new Gtk.TreeExpander ();
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
                margin_top = 9, margin_bottom = 9, margin_end = 10
            };
            icon = new Gtk.Image ();
            label = new Gtk.Label (null) { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
            count = new Gtk.Label (null);
            count.add_css_class ("folder-count");
            content.append (icon);
            content.append (label);
            content.append (count);
            expander.child = content;
            var overlay = new Gtk.Overlay () { child = expander };
            insertion = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.START, visible = false, can_target = false,
                margin_start = 8, margin_end = 8, height_request = 8
            };
            var marker = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            marker.add_css_class ("folder-insertion-marker");
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
            line.add_css_class ("folder-insertion-line");
            insertion.append (marker);
            insertion.append (line);
            overlay.add_overlay (insertion);
            append (overlay);

            var context = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
            context.pressed.connect ((presses, x, y) => {
                if (folder != null) {
                    context.set_state (Gtk.EventSequenceState.CLAIMED);
                    sidebar.select_folder (folder);
                    sidebar.show_menu (this, folder, x, y);
                }
            });
            add_controller (context);
            var source = new Gtk.DragSource () { actions = Gdk.DragAction.MOVE, button = Gdk.BUTTON_PRIMARY };
            source.prepare.connect (() => {
                if (folder == null || folder.is_account || !sidebar.data.contains_folder (folder)) { return null; }
                var transparent = new Gdk.MemoryTexture (1, 1, Gdk.MemoryFormat.R8G8B8A8_PREMULTIPLIED,
                    new Bytes (new uint8[] { 0, 0, 0, 0 }), 4);
                source.set_icon (transparent, 0, 0);
                var value = Value (typeof (Folder));
                value.set_object (folder);
                return new Gdk.ContentProvider.for_value (value);
            });
            add_controller (source);
            var target = new Gtk.DropTarget (typeof (Folder), Gdk.DragAction.MOVE) { preload = true };
            target.set_gtypes ({ typeof (Folder), typeof (ConversationDrag) });
            target.enter.connect ((x, y) => highlight_drop (target, y));
            target.motion.connect ((x, y) => highlight_drop (target, y));
            target.leave.connect (clear_drop);
            target.drop.connect ((value, x, y) => {
                clear_drop ();
                var destination = folder;
                if (destination == null) { return false; }
                var source_folder = value.get_object () as Folder;
                if (source_folder != null) {
                    return sidebar.operations.reorder (source_folder, destination, y >= get_height () / 2.0);
                }
                var messages = value.get_object () as ConversationDrag;
                return messages != null && sidebar.operations.move (messages, destination);
            });
            add_controller (target);
        }

        public void bind_folder (Gtk.TreeListRow row) {
            unbind_folder ();
            folder = (Folder) row.item;
            expander.list_row = row;
            update_row ();
            changed_handler = folder.notify.connect (update_row);
            children_handler = folder.children.items_changed.connect (update_row);
        }

        public void unbind_folder () {
            if (folder != null) {
                folder.disconnect (changed_handler);
                folder.children.disconnect (children_handler);
            }
            folder = null;
            expander.list_row = null;
            clear_drop ();
        }

        private void update_row () {
            label.label = folder.name;
            label.tooltip_text = folder.is_account ? folder.account : folder.name;
            icon.icon_name = folder.icon_name;
            count.label = folder.unread > 0 ? folder.unread.to_string () : "";
            expander.hide_expander = folder.children.get_n_items () == 0;
            if (folder.is_account) { label.add_css_class ("heading"); }
            else { label.remove_css_class ("heading"); }
        }

        private Gdk.DragAction highlight_drop (Gtk.DropTarget target, double y) {
            clear_drop ();
            var value = target.get_value ();
            if (folder == null || value == null) { return 0; }
            var source = value.get_object () as Folder;
            if (source != null && source != folder && !source.is_account && !folder.is_account &&
                source.parent != null && source.parent == folder.parent && sidebar.data.contains_folder (source)) {
                insertion.valign = y < get_height () / 2.0 ? Gtk.Align.START : Gtk.Align.END;
                insertion.visible = true;
                return Gdk.DragAction.MOVE;
            }
            var messages = value.get_object () as ConversationDrag;
            if (messages != null && sidebar.operations.can_move (messages, folder)) {
                add_css_class ("mail-drop-target");
                return Gdk.DragAction.MOVE;
            }
            return 0;
        }

        private void clear_drop () {
            insertion.visible = false;
            remove_css_class ("mail-drop-target");
        }
    }
}
