/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace Mail {
    public class Recipient : Object {
        public string name;
        public string email;
        public uint rank;
        public int64 last_used;

        public Recipient (string name, string email, uint rank, int64 last_used) {
            this.name = name;
            this.email = email;
            this.rank = rank;
            this.last_used = last_used;
        }

        public string formatted () {
            var address = new Camel.InternetAddress ();
            address.add (name == "" ? null : name, email);
            return address.format ();
        }
    }

    public class RecipientStore : Object {
        public signal void changed ();
        private HashTable<string, Recipient> addresses = new HashTable<string, Recipient> (str_hash, str_equal);
        private HashTable<string, Recipient> contacts = new HashTable<string, Recipient> (str_hash, str_equal);
        private Gee.HashSet<Camel.Folder> learning_folders = new Gee.HashSet<Camel.Folder> ();
        private static RecipientStore? instance;
        public bool history_enabled { get; private set; }
        private string filename;
        private uint pending_save;

        public static unowned RecipientStore get_default () {
            if (instance == null) {
                instance = new RecipientStore (
                    Path.build_filename (Environment.get_user_data_dir (), APPLICATION_ID, "recipient-history.gv"),
                    Granite.Services.System.history_is_enabled ());
            }
            return instance;
        }

        public static void flush_pending () {
            if (instance != null) { instance.flush (); }
        }

        public RecipientStore (string filename, bool history_enabled = true) {
            this.filename = filename;
            this.history_enabled = history_enabled;
            if (!history_enabled) { return; }
            try {
                string contents;
                FileUtils.get_contents (filename, out contents);
                var saved = Variant.parse (new VariantType ("a(ssux)"), contents);
                var iter = saved.iterator ();
                string name, email;
                uint rank;
                int64 last_used;
                while (iter.next ("(ssux)", out name, out email, out rank, out last_used)) {
                    remember (name, email, uint.min (rank, 100), last_used);
                }
            } catch (Error error) { }
        }

        /* ----- Address Sources ----- */
        public void remember_header (string? header, uint rank = 1, int64 last_used = 0) {
            if (header == null || header == "") { return; }
            var parsed = new Camel.InternetAddress ();
            parsed.decode (header);
            for (int i = 0; i < parsed.length (); i++) {
                unowned string? name, email;
                if (parsed.get (i, out name, out email) && email != null) {
                    remember (name ?? "", email, rank, last_used);
                }
            }
        }

        public void replace_contacts (GenericArray<Recipient> current) {
            contacts.remove_all ();
            foreach (var contact in current.data) {
                contacts.insert (contact.email.casefold (), contact);
            }
            changed ();
        }

        public void remember_message (Camel.MessageInfo message, bool sent) {
            if ((message.flags & (Camel.MessageFlags.DELETED | Camel.MessageFlags.JUNK | Camel.MessageFlags.DRAFT)) != 0) { return; }
            remember_header (message.from, 1, message.date_sent);
            remember_header (message.to, sent ? 10u : 1u, message.date_sent);
            remember_header (message.cc, sent ? 10u : 1u, message.date_sent);
        }

        public async void learn_folder (Camel.Folder folder, bool sent, Cancellable? cancellable = null) {
            if (!learning_folders.add (folder)) { return; }
            try {
                yield collect_headers (folder, sent, cancellable);
            } finally {
                learning_folders.remove (folder);
            }
        }

        private async void collect_headers (Camel.Folder folder, bool sent, Cancellable? cancellable) {
            if (!history_enabled || (folder.get_flags () & (Camel.FolderFlags.IS_JUNK | Camel.FolderFlags.IS_TRASH)) != 0) { return; }
#if HAS_CAMEL_3_58
            var source = folder.dup_uids ();
#else
            unowned var source = folder.get_uids ();
#endif /* HAS_CAMEL_3_58 */
            var uids = new GenericArray<string> ();
            foreach (var uid in source.data) { uids.add (uid); }
            folder.sort_uids (uids);
            int end = int.max (0, (int) uids.length - 2000);
            for (int i = (int) uids.length - 1; i >= end; i--) {
                if (cancellable != null && cancellable.is_cancelled ()) { return; }
                var message = folder.get_message_info (uids[(uint) i]);
                if (message != null) { remember_message (message, sent); }
                if (i % 100 == 0) {
                    Idle.add (() => { collect_headers.callback (); return Source.REMOVE; });
                    yield;
                }
            }
        }

        public void remember (string input_name, string input_email, uint rank, int64 last_used = 0) {
            if (!history_enabled) { return; }
            string email = input_email.strip ();
            string name = input_name.replace ("\r", " ").replace ("\n", " ").strip ();
            if (!email.contains ("@") || email.contains ("\r") || email.contains ("\n") || email.contains (" ")) { return; }
            string key = email.casefold ();
            last_used = int64.min (last_used, get_real_time () / 1000000);
            var existing = addresses.lookup (key);
            if (existing != null) {
                bool renamed = name != "" && name != existing.name && (existing.name == "" || rank > existing.rank);
                if (!renamed && rank <= existing.rank && last_used <= existing.last_used) { return; }
                if (renamed) { existing.name = name; }
                existing.rank = uint.max (existing.rank, rank);
                existing.last_used = int64.max (existing.last_used, last_used);
            } else {
                addresses.insert (key, new Recipient (name, email, rank, last_used));
            }
            if (addresses.size () > 2100) { prune (); }
            if (pending_save == 0) {
                pending_save = Timeout.add (250, () => {
                    pending_save = 0;
                    flush ();
                    changed ();
                    return Source.REMOVE;
                });
            }
        }

        /* ----- Suggestions and Private History ----- */
        public GenericArray<Recipient> search (string query) {
            string needle = query.casefold ().strip ();
            var found = new GenericArray<Recipient> ();
            foreach (var item in contacts.get_values ()) {
                if (item.email.casefold ().contains (needle) || item.name.casefold ().contains (needle)) { found.add (item); }
            }
            foreach (var item in addresses.get_values ()) {
                if (!contacts.contains (item.email.casefold ()) &&
                    (item.email.casefold ().contains (needle) || item.name.casefold ().contains (needle))) { found.add (item); }
            }
            sort_matches (found, needle);
            return found;
        }

        private void sort_matches (GenericArray<Recipient> found, string needle) {
            found.sort_with_data ((a, b) => {
                if (a.rank != b.rank) { return a.rank > b.rank ? -1 : 1; }
                bool a_prefix = a.email.casefold ().has_prefix (needle) || a.name.casefold ().has_prefix (needle);
                bool b_prefix = b.email.casefold ().has_prefix (needle) || b.name.casefold ().has_prefix (needle);
                if (a_prefix != b_prefix) { return a_prefix ? -1 : 1; }
                if (a.last_used != b.last_used) { return a.last_used > b.last_used ? -1 : 1; }
                return strcmp (a.email, b.email);
            });
        }

        private void prune () {
            var ordered = new GenericArray<Recipient> ();
            foreach (var item in addresses.get_values ()) { ordered.add (item); }
            sort_matches (ordered, "");
            for (uint i = 2000; i < ordered.length; i++) { addresses.remove (ordered[i].email.casefold ()); }
        }

        public void flush () {
            if (!history_enabled) { return; }
            if (pending_save != 0) { Source.remove (pending_save); pending_save = 0; }
            prune ();
            var saved = new VariantBuilder (new VariantType ("a(ssux)"));
            foreach (var item in addresses.get_values ()) {
                if (item.rank < 1000) { saved.add ("(ssux)", item.name, item.email, item.rank, item.last_used); }
            }
            try {
                DirUtils.create_with_parents (Path.get_dirname (filename), 0700);
                FileUtils.set_contents_full (filename, saved.end ().print (true), -1, FileSetContentsFlags.CONSISTENT, 0600);
            } catch (Error error) { debug ("Unable to save recipient history: %s", error.message); }
        }
    }

    public class RecipientToken : Object {
        public static void bounds (string text, int cursor, out int start, out int end) {
            int position = text.index_of_nth_char (int.max (0, int.min (cursor, (int) text.char_count ())));
            start = 0;
            end = text.length;
            bool quoted = false, angled = false;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (c == '\\' && quoted) { i++; continue; }
                if (c == '"') { quoted = !quoted; }
                if (!quoted && c == '<') { angled = true; }
                if (!quoted && c == '>') { angled = false; }
                if (!quoted && !angled && (c == ',' || c == ';')) {
                    if (i < position) { start = i + 1; }
                    else { end = i; break; }
                }
            }
            while (start < end && (text[start] == ' ' || text[start] == '\t')) { start++; }
        }
    }
}
