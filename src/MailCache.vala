/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class MailCache : Object {
        private const string FORMAT = "a(sssuubbbb)";
        private string directory = Path.build_filename (Environment.get_user_cache_dir (), Application.ID, "folders");

        private string filename (Folder account) {
            return Path.build_filename (directory, Checksum.compute_for_string (ChecksumType.SHA256, account.id) + ".gv");
        }

        public void restore (Folder account) {
            string contents;
            if (!FileUtils.test (filename (account), FileTest.EXISTS)) { return; }
            try {
                FileUtils.get_contents (filename (account), out contents);
                var snapshot = Variant.parse (new VariantType (FORMAT), contents);
                var parents = new HashTable<string, Folder> (str_hash, str_equal);
                parents.insert ("", account);
                var iter = snapshot.iterator ();
                string path, name, parent;
                uint role, unread;
                bool selectable, writable, can_create, system_folder;
                while (iter.next ("(sssuubbbb)", out path, out name, out parent, out role, out unread,
                    out selectable, out writable, out can_create, out system_folder)) {
                    if (path == "" || path == parent || parents.contains (path) || !parents.contains (parent) || role > (uint) FolderRole.JUNK) { continue; }
                    var folder = new Folder (name, icon_for_role ((FolderRole) role), account.account, false,
                        (FolderRole) role, account.id + "/" + path) {
                        live = true, remote_name = path, unread = unread, selectable = selectable,
                        writable = writable, can_create = can_create, system_folder = system_folder
                    };
                    parents.lookup (parent).add_child (folder);
                    parents.insert (path, folder);
                }
            } catch (Error error) { debug ("Unable to restore folder cache: %s", error.message); }
        }

        public void save (Folder account) {
            var snapshot = new VariantBuilder (new VariantType (FORMAT));
            append (snapshot, account);
            try {
                DirUtils.create_with_parents (directory, 0700);
                FileUtils.set_contents (filename (account), snapshot.end ().print (true));
            } catch (Error error) { debug ("Unable to save folder cache: %s", error.message); }
        }

        private void append (VariantBuilder snapshot, Folder parent) {
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var folder = (Folder) parent.children.get_item (i);
                snapshot.add ("(sssuubbbb)", folder.remote_name, folder.name, parent.is_account ? "" : parent.remote_name,
                    (uint) folder.role, folder.unread, folder.selectable, folder.writable, folder.can_create, folder.system_folder);
                append (snapshot, folder);
            }
        }

        public static string icon_for_role (FolderRole role) {
            switch (role) {
                case FolderRole.INBOX: return "folder-download-symbolic";
                case FolderRole.TRASH: return "user-trash-symbolic";
                case FolderRole.JUNK: return "mail-mark-junk-symbolic";
                case FolderRole.SENT: return "mail-send-symbolic";
                case FolderRole.DRAFTS: return "document-edit-symbolic";
                case FolderRole.ARCHIVE: return "package-x-generic-symbolic";
                case FolderRole.STARRED: return "starred-symbolic";
                default: return "folder-symbolic";
            }
        }
    }
}
