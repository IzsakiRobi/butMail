/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    public class Signature : Object {
        public string id;
        public string name;
        public string html;

        public Signature (string id, string name, string html) {
            this.id = id;
            this.name = name;
            this.html = html;
        }
    }

    public class Signatures : Object {
        public ListStore items { get; private set; }
        public bool ready { get; private set; }
        public string? error_message { get; private set; }
        public signal void changed ();
        private E.SourceRegistry? registry;
        private bool loading;
        private bool reload;

        public Signatures () { items = new ListStore (typeof (Signature)); }

        public async void load () {
            reload = true;
            if (loading) { return; }
            loading = true;
            do {
                reload = false;
                error_message = null;
                try {
                    if (registry == null) {
                        registry = yield new E.SourceRegistry (null);
                        registry.source_added.connect (source_changed);
                        registry.source_removed.connect (source_changed);
                        registry.source_changed.connect (source_changed);
                    }
                    var loaded = new GenericArray<Signature> ();
                    foreach (var source in registry.list_sources (E.SOURCE_EXTENSION_MAIL_SIGNATURE)) {
                        string contents;
                        size_t length;
                        if (!yield source.mail_signature_load (Priority.DEFAULT, null, out contents, out length)) { continue; }
                        unowned var extension = (E.SourceMailSignature) source.get_extension (E.SOURCE_EXTENSION_MAIL_SIGNATURE);
                        string html = extension.mime_type == "text/html" ? contents : Markup.escape_text (contents).replace ("\n", "<br>");
                        loaded.add (new Signature (source.uid, source.display_name, html));
                    }
                    loaded.sort ((a, b) => a.name.collate (b.name));
                    items.splice (0, items.get_n_items (), loaded.data);
                } catch (Error error) { error_message = error.message; }
            } while (reload);
            loading = false;
            ready = true;
            changed ();
        }

        private void source_changed (E.Source source) {
            if (source.has_extension (E.SOURCE_EXTENSION_MAIL_SIGNATURE) || source.has_extension (E.SOURCE_EXTENSION_MAIL_IDENTITY)) {
                load.begin ();
            }
        }

        public Signature? find (string id) {
            for (uint i = 0; i < items.get_n_items (); i++) {
                var item = (Signature) items.get_item (i);
                if (item.id == id) { return item; }
            }
            return null;
        }

        public string default_id (Settings settings, string account) {
            string key = account.strip ().down ();
            var saved = settings.get_value ("default-signatures").lookup_value (key, VariantType.STRING);
            if (saved != null) { return saved.get_string (); }
            if (registry != null) {
                foreach (var source in registry.list_enabled (E.SOURCE_EXTENSION_MAIL_IDENTITY)) {
                    unowned var identity = (E.SourceMailIdentity) source.get_extension (E.SOURCE_EXTENSION_MAIL_IDENTITY);
                    if (identity.address != null && identity.address.strip ().down () == key && identity.signature_uid != null) {
                        if (find (identity.signature_uid) != null) { return identity.signature_uid; }
                    }
                }
            }
            return "none";
        }

        public string html_for (string id) {
            var item = find (id);
            return item != null ? item.html : "";
        }

        public static void set_default (Settings settings, string account, string id, string? previous = null) {
            string key = account.strip ().down ();
            var builder = new VariantBuilder (new VariantType ("a{ss}"));
            var entries = settings.get_value ("default-signatures").iterator ();
            string address, saved;
            while (entries.next ("{ss}", out address, out saved)) {
                if (address != key && address != previous) { builder.add ("{ss}", address, saved); }
            }
            builder.add ("{ss}", key, id);
            settings.set_value ("default-signatures", builder.end ());
        }

        public async void save (Signature? item, string name, string html) throws Error {
            if (registry == null) { throw new IOError.NOT_CONNECTED ("Signatures are not available yet."); }
            var source = item != null ? registry.ref_source (item.id) : new E.Source.with_uid (Uuid.string_random (), null);
            if (source == null) { throw new IOError.NOT_FOUND ("This signature no longer exists."); }
            source.display_name = name;
            unowned var extension = (E.SourceMailSignature) source.get_extension (E.SOURCE_EXTENSION_MAIL_SIGNATURE);
            extension.mime_type = "text/html";
            if (!yield source.mail_signature_replace (html, html.length, Priority.DEFAULT, null)) {
                throw new IOError.FAILED ("The signature could not be saved.");
            }
            if (item == null) { yield registry.commit_source (source, null); }
            else { yield source.write (null); }
            yield load ();
        }

        public async void remove (Signature item) throws Error {
            var source = registry != null ? registry.ref_source (item.id) : null;
            if (source == null) { throw new IOError.NOT_FOUND ("This signature no longer exists."); }
            yield source.remove (null);
            yield load ();
        }
    }
}
