/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class FolderPickerPopover : Object {
        public Gtk.PopoverMenu popover { get; private set; }
        public signal void folder_selected (Folder folder);
        private Menu folders = new Menu ();
        private Gtk.SearchEntry search;
        private GenericArray<Folder> destinations = new GenericArray<Folder> ();
        private Folder? account;
        private Folder? source;

        public FolderPickerPopover () {
            var root = new Menu ();
            var search_item = new MenuItem (null, null);
            search_item.set_attribute ("custom", "s", "folder-search");
            root.append_item (search_item);
            root.append_section (null, folders);
            popover = new Gtk.PopoverMenu.from_model (root);
            search = new Gtk.SearchEntry () {
                placeholder_text = "Search folders", width_request = 240,
                margin_start = 6, margin_end = 6, margin_top = 4, margin_bottom = 4
            };
            popover.add_child (search, "folder-search");
            search.search_changed.connect (populate);
            var group = new SimpleActionGroup ();
            var move = new SimpleAction ("move", VariantType.UINT32);
            move.activate.connect ((value) => {
                uint index = value.get_uint32 ();
                if (index < destinations.length) {
                    var destination = destinations[index];
                    popover.popdown ();
                    folder_selected (destination);
                }
            });
            group.add_action (move);
            popover.insert_action_group ("folders", group);
        }

        public void set_source (Folder account, Folder source) {
            this.account = account;
            this.source = source;
            search.text = "";
            populate ();
            search.grab_focus ();
        }

        private void populate () {
            folders.remove_all ();
            destinations = new GenericArray<Folder> ();
            if (account != null) {
                add_folders (account, "");
            }
            if (destinations.length == 0) {
                folders.append ("No Matching Folders", null);
            }
        }

        private void add_folders (Folder parent, string path) {
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var folder = (Folder) parent.children.get_item (i);
                if (folder.role == FolderRole.STARRED) {
                    continue;
                }
                string full_path = path == "" ? folder.name : path + " / " + folder.name;
                if (folder != source && folder.selectable && folder.writable && full_path.casefold ().contains (search.text.strip ().casefold ())) {
                    var item = new MenuItem (full_path, null);
                    item.set_icon (new ThemedIcon (folder.icon_name));
                    item.set_action_and_target_value ("folders.move", new Variant.uint32 (destinations.length));
                    destinations.add (folder);
                    folders.append_item (item);
                }
                add_folders (folder, full_path);
            }
        }
    }
}
