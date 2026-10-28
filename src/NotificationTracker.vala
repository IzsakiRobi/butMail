/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    private class MailNotification : Object {
        public string folder;
        public string uid;

        public MailNotification (string folder, string uid) {
            this.folder = folder;
            this.uid = uid;
        }
    }

    public class NotificationTracker : Object {
        public signal void withdrawal_requested (string id);
        private HashTable<string, MailNotification> pending = new HashTable<string, MailNotification> (str_hash, str_equal);
        private string filename;

        public NotificationTracker (string filename) {
            this.filename = filename;
            try {
                string contents;
                FileUtils.get_contents (filename, out contents);
                var saved = Variant.parse (new VariantType ("a(ss)"), contents);
                var iter = saved.iterator ();
                string folder, uid;
                while (iter.next ("(ss)", out folder, out uid)) { track (folder, uid); }
            } catch (Error error) { }
        }

        public string track (string folder, string uid) {
            string id = "new-mail-" + Checksum.compute_for_string (ChecksumType.SHA256,
                new Variant ("(ss)", folder, uid).print (false));
            pending.insert (id, new MailNotification (folder, uid));
            return id;
        }

        public void resolve (string folder, HashTable<string, bool> unread) {
            var resolved = new GenericArray<string> ();
            pending.foreach ((id, item) => {
                if (item.folder == folder && !unread.contains (item.uid)) { resolved.add (id); }
            });
            foreach (var id in resolved.data) {
                pending.remove (id);
                withdrawal_requested (id);
            }
        }

        public void save () {
            var saved = new VariantBuilder (new VariantType ("a(ss)"));
            foreach (var item in pending.get_values ()) { saved.add ("(ss)", item.folder, item.uid); }
            try {
                DirUtils.create_with_parents (Path.get_dirname (filename), 0700);
                FileUtils.set_contents_full (filename, saved.end ().print (true), -1, FileSetContentsFlags.CONSISTENT, 0600);
            } catch (Error error) { debug ("Unable to save notification state: %s", error.message); }
        }
    }
}
