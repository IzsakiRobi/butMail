/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
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
        private string filename;
        private uint pending_save;

        public RecipientStore (string filename) {
            this.filename = filename;
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

        public void remember (string input_name, string input_email, uint rank, int64 last_used = 0) {
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
            foreach (var item in addresses.get_values ()) {
                if (item.email.casefold ().contains (needle) || item.name.casefold ().contains (needle)) { found.add (item); }
            }
            found.sort_with_data ((a, b) => {
                if (a.rank != b.rank) { return a.rank > b.rank ? -1 : 1; }
                bool a_prefix = a.email.casefold ().has_prefix (needle) || a.name.casefold ().has_prefix (needle);
                bool b_prefix = b.email.casefold ().has_prefix (needle) || b.name.casefold ().has_prefix (needle);
                if (a_prefix != b_prefix) { return a_prefix ? -1 : 1; }
                if (a.last_used != b.last_used) { return a.last_used > b.last_used ? -1 : 1; }
                return strcmp (a.email, b.email);
            });
            return found;
        }

        private void prune () {
            var ordered = search ("");
            for (uint i = 2000; i < ordered.length; i++) { addresses.remove (ordered[i].email.casefold ()); }
        }

        public void flush () {
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
            int position = text.index_of_nth_char (cursor);
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
