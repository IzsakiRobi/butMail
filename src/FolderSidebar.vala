/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class FolderSidebar : Gtk.Box {
        public signal void folder_selected (Folder folder);
        public MailData data { get; private set; }
        public MailOperations operations { get; private set; }
        private Gtk.SingleSelection selection;
        private Gtk.TreeListModel tree;
        private Folder? selected_before;
        private HashTable<string, bool> expanded = new HashTable<string, bool> (str_hash, str_equal);
        private Gtk.PopoverMenu? context_menu;
        private ulong changing_handler;
        private ulong changed_handler;

        public FolderSidebar (MailData data, MailOperations operations) {
            Object (orientation: Gtk.Orientation.VERTICAL);
            this.data = data;
            this.operations = operations;
            tree = new Gtk.TreeListModel (data.accounts, false, true, (item) => ((Folder) item).children);
            selection = new Gtk.SingleSelection (tree) { autoselect = false };
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((item) => { ((Gtk.ListItem) item).child = new FolderRow (this); });
            factory.bind.connect ((item) => {
                var list_item = (Gtk.ListItem) item;
                ((FolderRow) list_item.child).bind_folder ((Gtk.TreeListRow) list_item.item);
            });
            factory.unbind.connect ((item) => { ((FolderRow) ((Gtk.ListItem) item).child).unbind_folder (); });
            var list = new Gtk.ListView (selection, factory) { single_click_activate = false };
            list.add_css_class ("navigation-sidebar");
            list.activate.connect ((position) => {
                var row = tree.get_row (position);
                if (((Folder) row.item).is_account) { row.expanded = !row.expanded; }
            });
            selection.notify["selected-item"].connect (() => {
                var row = selection.selected_item as Gtk.TreeListRow;
                if (row != null && !((Folder) row.item).is_account) { folder_selected ((Folder) row.item); }
            });
            append (new Gtk.ScrolledWindow () { child = list, vexpand = true, hscrollbar_policy = Gtk.PolicyType.NEVER });
            changing_handler = data.folders_changing.connect (capture_state);
            changed_handler = data.folders_changed.connect (restore_state);
        }

        public void select_folder (Folder folder) {
            if (folder.parent != null) { expand_parent (folder.parent); }
            for (uint i = 0; i < tree.get_n_items (); i++) {
                if (tree.get_row (i).item == folder) {
                    selection.selected = i;
                    return;
                }
            }
        }

        private void expand_parent (Folder folder) {
            if (folder.parent != null) { expand_parent (folder.parent); }
            for (uint i = 0; i < tree.get_n_items (); i++) {
                var row = tree.get_row (i);
                if (row.item == folder) { row.expanded = true; return; }
            }
        }

        private void capture_state () {
            expanded.remove_all ();
            var selected = selection.selected_item as Gtk.TreeListRow;
            selected_before = selected != null ? (Folder) selected.item : null;
            for (uint i = 0; i < tree.get_n_items (); i++) {
                var row = tree.get_row (i);
                expanded.insert (((Folder) row.item).id, row.expanded);
            }
        }

        private void restore_state (Folder? preferred) {
            for (uint i = 0; i < tree.get_n_items (); i++) {
                var row = tree.get_row (i);
                string id = ((Folder) row.item).id;
                if (expanded.contains (id)) { row.expanded = expanded.lookup (id); }
            }
            var selected = preferred ?? selected_before;
            if (selected != null && data.contains_folder (selected)) {
                var current = selection.selected_item as Gtk.TreeListRow;
                bool same = current != null && current.item == selected;
                select_folder (selected);
                if (same && preferred != null && !selected.is_account) { folder_selected (selected); }
            }
        }

        public void show_menu (Gtk.Widget anchor, Folder folder, double x, double y) {
            if (context_menu != null) { context_menu.popdown (); }
            var group = new SimpleActionGroup ();
            var create = new SimpleAction ("create", null);
            create.set_enabled (folder.can_create && folder.role != FolderRole.STARRED && !folder.is_in_trash ());
            create.activate.connect (() => edit_name (folder, null));
            group.add_action (create);
            var rename = new SimpleAction ("rename", null);
            rename.set_enabled (folder.writable && !folder.system_folder && !folder.is_account && folder.role == FolderRole.REGULAR && !folder.is_in_trash ());
            rename.activate.connect (() => {
                if (folder.parent != null) { edit_name (folder.parent, folder); }
            });
            group.add_action (rename);
            var trash = new SimpleAction ("trash", null);
            trash.set_enabled (rename.get_enabled ());
            trash.activate.connect (() => confirm_trash (folder));
            group.add_action (trash);
            var empty = new SimpleAction ("empty", null);
            empty.set_enabled (operations.can_empty_trash (folder));
            empty.activate.connect (() => operations.request_empty_trash (folder, this));
            group.add_action (empty);
            insert_action_group ("folder-menu", group);
            var menu = new Menu ();
            menu.append (folder.is_account ? "New Folder…" : "New Subfolder…", "folder-menu.create");
            if (!folder.is_account) {
                menu.append ("Rename…", "folder-menu.rename");
                menu.append ("Move Folder to Trash…", "folder-menu.trash");
            }
            if (folder.role == FolderRole.TRASH) { menu.append ("Empty Trash…", "folder-menu.empty"); }
            var popover = new Gtk.PopoverMenu.from_model (menu);
            popover.set_parent (anchor);
            popover.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
            popover.closed.connect (() => {
                if (popover.get_parent () != null) { popover.unparent (); }
                if (context_menu == popover) { context_menu = null; }
            });
            context_menu = popover;
            popover.popup ();
        }

        private void edit_name (Folder parent, Folder? existing) {
            var dialog = new FolderNameDialog (parent, existing);
            dialog.name_chosen.connect ((name) => {
                if (!data.contains_folder (parent) || MailOperations.validate_name (parent, name, existing) != null) { return; }
                operations.save_folder (parent, name, existing);
            });
            dialog.present (this);
        }

        private void confirm_trash (Folder folder) {
            var dialog = new Adw.AlertDialog ("Move Folder to Trash?", "The folder, its subfolders and their messages will be moved to Trash.");
            dialog.add_responses ("cancel", "Cancel", "trash", "Move to Trash", null);
            dialog.close_response = "cancel";
            dialog.default_response = "cancel";
            dialog.set_response_appearance ("trash", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((id) => { if (id == "trash") { operations.trash_folder (folder); } });
            dialog.present (this);
        }

        protected override void dispose () {
            if (changing_handler != 0) { data.disconnect (changing_handler); changing_handler = 0; }
            if (changed_handler != 0) { data.disconnect (changed_handler); changed_handler = 0; }
            if (context_menu != null && context_menu.get_parent () != null) { context_menu.unparent (); }
            base.dispose ();
        }
    }
}
