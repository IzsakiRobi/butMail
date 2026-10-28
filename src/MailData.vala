/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class MailData : Object {
        public ListStore accounts { get; private set; }

        private Settings settings;
        public signal void folders_changing ();
        public signal void folders_changed (Folder? preferred);

        public MailData (Settings settings) {
            this.settings = settings;
            accounts = new ListStore (typeof (Folder));
        }

        public void replace_accounts (Folder[] roots, Folder? preferred) {
            folders_changing ();
            accounts.splice (0, accounts.get_n_items (), roots);
            foreach (var root in roots) { restore_order (root); }
            folders_changed (preferred);
        }

        public void update_account (Folder account, Folder[] incoming, Folder? selected) {
            folders_changing ();
            var existing = new HashTable<string, Folder> (str_hash, str_equal);
            collect_folders (account, existing);
            merge_folders (account, incoming, existing);
            restore_order (account);
            bool retained = selected != null && contains_folder (selected);
            Folder? preferred = retained ? null : find_folder (account, FolderRole.INBOX);
            if (!retained && preferred == null && account.children.get_n_items () > 0) { preferred = (Folder) account.children.get_item (0); }
            folders_changed (preferred);
        }

        private void collect_folders (Folder parent, HashTable<string, Folder> folders) {
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var folder = (Folder) parent.children.get_item (i);
                folders.insert (folder.id, folder);
                collect_folders (folder, folders);
            }
        }

        private void merge_folders (Folder parent, Folder[] incoming, HashTable<string, Folder> existing) {
            var desired = new ListStore (typeof (Folder));
            foreach (var source in incoming) {
                var folder = existing.lookup (source.id) ?? source;
                if (folder != source) {
                    folder.name = source.name;
                    folder.icon_name = source.icon_name;
                    folder.role = source.role;
                    folder.unread = source.unread;
                    folder.writable = source.writable;
                    folder.selectable = source.selectable;
                    folder.can_create = source.can_create;
                    folder.system_folder = source.system_folder;
                }
                var children = new GenericArray<Folder> ();
                for (uint i = 0; i < source.children.get_n_items (); i++) { children.add ((Folder) source.children.get_item (i)); }
                merge_folders (folder, children.data, existing);
                folder.parent = parent;
                desired.append (folder);
            }
            var ordered = new GenericArray<Object> ();
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var child = (Folder) parent.children.get_item (i);
                uint position;
                if (desired.find (child, out position)) { ordered.add (child); desired.remove (position); }
                else if (child.parent == parent) { child.parent = null; }
            }
            for (uint i = 0; i < desired.get_n_items (); i++) { ordered.add (desired.get_item (i)); }
            parent.children.splice (0, parent.children.get_n_items (), ordered.data);
        }

        public bool contains_folder (Folder folder) {
            Folder root = folder;
            while (root.parent != null) {
                uint position;
                if (!root.parent.children.find (root, out position)) {
                    return false;
                }
                root = root.parent;
            }
            uint index;
            return accounts.find (root, out index);
        }

        public void remember_order (Folder parent) {
            string[] ids = {};
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                ids += ((Folder) parent.children.get_item (i)).id;
            }
            var existing = settings.get_value ("folder-order");
            var order = new VariantBuilder (new VariantType ("a{sas}"));
            for (uint i = 0; i < existing.n_children (); i++) {
                var entry = existing.get_child_value (i);
                if (entry.get_child_value (0).get_string () != parent.id) { order.add_value (entry); }
            }
            order.add_value (new Variant.dict_entry (new Variant.string (parent.id), new Variant.strv (ids)));
            settings.set_value ("folder-order", order.end ());
        }

        private void restore_order (Folder parent) {
            var order = settings.get_value ("folder-order").lookup_value (parent.id, VariantType.STRING_ARRAY);
            var sorted = new ListStore (typeof (Folder));
            if (order != null) {
                foreach (var id in order.dup_strv ()) {
                    for (uint i = 0; i < parent.children.get_n_items (); i++) {
                        var child = (Folder) parent.children.get_item (i);
                        uint duplicate;
                        if (child.id == id && !sorted.find (child, out duplicate)) {
                            sorted.append (child);
                        }
                    }
                }
            }
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var child = (Folder) parent.children.get_item (i);
                uint duplicate;
                if (!sorted.find (child, out duplicate)) {
                    sorted.append (child);
                }
            }
            Object[] children = new Object[sorted.get_n_items ()];
            for (uint i = 0; i < sorted.get_n_items (); i++) {
                children[i] = sorted.get_item (i);
            }
            parent.children.splice (0, parent.children.get_n_items (), children);
            foreach (var child in children) {
                restore_order ((Folder) child);
            }
        }

        public Folder? find_folder (Folder root, FolderRole role) {
            if (root.role == role) {
                return root;
            }
            for (uint i = 0; i < root.children.get_n_items (); i++) {
                var found = find_folder ((Folder) root.children.get_item (i), role);
                if (found != null) {
                    return found;
                }
            }
            return null;
        }

        public Folder? account_for (Folder folder) {
            while (folder.parent != null) { folder = folder.parent; }
            uint position;
            return accounts.find (folder, out position) ? folder : null;
        }

    }
}
