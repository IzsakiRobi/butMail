/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    private class AvatarEntry : Object {
        public Gdk.Texture? texture;
        public bool ready { get; set; }
        public int64 expires;
    }

    public class AvatarStore : Object {
        public signal void changed ();
        private Settings settings;
        private Soup.Session session;
        private HashTable<string, AvatarEntry> entries = new HashTable<string, AvatarEntry> (str_hash, str_equal);
        private GenericArray<E.BookClient> books = new GenericArray<E.BookClient> ();
        private bool books_ready { get; set; }
        private Cancellable cancellable = new Cancellable ();
        private uint generation;
        private int64 anylogo_retry_after;
        private int64 company_retry_after;
        private string directory = Path.build_filename (Environment.get_user_cache_dir (), Application.ID, "avatars");

        public AvatarStore (Settings settings) {
            this.settings = settings;
            session = (Soup.Session) Object.new (typeof (Soup.Session), "timeout", 8u,
                "max-conns", 4, "max-conns-per-host", 4, "user-agent", "butMail/0.5");
            settings.changed["load-remote-avatars"].connect (invalidate);
            settings.changed["show-avatars"].connect (invalidate);
            LogoCredentials.get_default ().changed.connect (invalidate);
            prepare_books.begin ();
        }

        private void invalidate () {
            generation++;
            cancellable.cancel ();
            cancellable = new Cancellable ();
            entries.remove_all ();
            changed ();
        }

        /* ----- Address Book Photos ----- */
        private async void prepare_books () {
            try {
                var registry = yield new E.SourceRegistry (null);
                foreach (var source in registry.list_enabled (E.SOURCE_EXTENSION_ADDRESS_BOOK)) {
                    var job = new Cancellable ();
                    uint timeout = Timeout.add_seconds (3, () => { job.cancel (); return Source.REMOVE; });
                    try { books.add (yield E.BookClient.connect (source, 1, job)); }
                    catch (Error error) { }
                    if (!job.is_cancelled ()) { Source.remove (timeout); }
                }
            } catch (Error error) { }
            books_ready = true;
        }

        private async Gdk.Texture? contact_photo (string email, Cancellable job) {
            if (!books_ready) {
                ulong handler = notify["books-ready"].connect (() => contact_photo.callback ());
                yield;
                disconnect (handler);
            }
            if (job.is_cancelled ()) { return null; }
            var query = E.BookQuery.field_test (E.ContactField.EMAIL, E.BookQueryTest.IS, email);
            foreach (var book in books) {
                var lookup = new Cancellable ();
                ulong handler = job.cancelled.connect (() => lookup.cancel ());
                uint timeout = Timeout.add_seconds (2, () => { lookup.cancel (); return Source.REMOVE; });
                try {
                    SList<E.Contact> contacts;
                    yield book.get_contacts (query.to_string (), lookup, out contacts);
                    foreach (var contact in contacts) {
                        var photo = contact.photo;
                        if (photo == null) { continue; }
                        var data = photo.type == E.ContactPhotoType.INLINED ? photo.get_inlined () : null;
                        if (data != null) {
                            var image = decode (new Bytes (data), false, false);
                            if (image != null) { return image; }
                        }
                        string? uri = photo.type == E.ContactPhotoType.URI ? photo.get_uri () : null;
                        if (uri != null && uri.has_prefix ("file:")) {
                            uint8[] bytes;
                            yield File.new_for_uri (uri).load_contents_async (job, out bytes, null);
                            var image = decode (new Bytes (bytes), false, false);
                            if (image != null) { return image; }
                        }
                    }
                } catch (Error error) { }
                finally {
                    if (!lookup.is_cancelled ()) { Source.remove (timeout); }
                    job.disconnect (handler);
                }
                if (job.is_cancelled ()) { return null; }
            }
            return null;
        }

        /* ----- Address Book Recipients ----- */
        public async void populate_recipients (RecipientStore recipients) {
            if (!books_ready) {
                ulong handler = notify["books-ready"].connect (() => populate_recipients.callback ());
                yield;
                disconnect (handler);
            }
            var query = E.BookQuery.any_field_contains ("");
            foreach (var book in books) {
                var job = new Cancellable ();
                uint timeout = Timeout.add_seconds (3, () => { job.cancel (); return Source.REMOVE; });
                try {
                    SList<E.Contact> contacts;
                    yield book.get_contacts (query.to_string (), job, out contacts);
                    foreach (var contact in contacts) {
                        var emails = contact.get<GLib.List<string>> (E.ContactField.EMAIL);
                        foreach (var email in emails) { recipients.remember (contact.full_name ?? "", email, 1000); }
                    }
                } catch (Error error) { }
                finally { if (!job.is_cancelled ()) { Source.remove (timeout); } }
            }
        }

        /* ----- Ordered Avatar Sources ----- */
        public async Gdk.Texture? lookup (string address, int minimum_size) {
            string email = address.strip ().down ();
            int separator = email.last_index_of ("@");
            if (separator <= 0 || !settings.get_boolean ("show-avatars")) { return null; }
            uint version = generation;
            var job = cancellable;
            string hash = Checksum.compute_for_string (ChecksumType.SHA256, email);
            var contact = yield fetch ("contact-" + hash, null, email, job, minimum_size);
            if (version != generation || job.is_cancelled ()) { return null; }
            if (contact != null || !settings.get_boolean ("load-remote-avatars")) { return contact; }
            string domain = Hostname.to_ascii (email.substring (separator + 1)) ?? "";
            if (!Regex.match_simple ("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,63}$", domain)) { return null; }
            Gdk.Texture? image = yield fetch ("gravatar-" + hash,
                "https://www.gravatar.com/avatar/" + hash + "?s=256&d=404&r=g", null, job, minimum_size);
            if (version != generation || job.is_cancelled ()) { return null; }
            if (image != null) { return image; }
            try { domain = Soup.tld_get_base_domain (domain); }
            catch (Error error) { return null; }
            var credentials = LogoCredentials.get_default ();
            yield credentials.ensure_ready ();
            if (version != generation) { return null; }
            if (credentials.key != null && credentials.key != "") {
                string token = credentials.key;
                string key_hash = Checksum.compute_for_string (ChecksumType.SHA256, token);
                image = yield fetch ("logodev-" + domain + "-" + key_hash,
                    "https://img.logo.dev/" + domain + "?size=256&format=png&fallback=404&token=" + Uri.escape_string (token), null, job, minimum_size);
            }
            if (version != generation || job.is_cancelled ()) { return null; }
            if (image == null) {
                image = yield fetch ("anylogo-" + domain,
                    "https://img.anylogo.dev/" + domain + "?size=256&fallback=404", null, job, minimum_size);
            }
            if (version != generation || job.is_cancelled ()) { return null; }
            if (image == null) {
                string company_domain = domain == "firefox.com" ? "Firefox.com" : domain;
                image = yield fetch ("companyenrich-" + company_domain,
                    "https://api.companyenrich.com/logo/" + company_domain, null, job, minimum_size);
            }
            return version == generation && !job.is_cancelled () ? image : null;
        }

        /* ----- Shared Requests and Cache ----- */
        private async Gdk.Texture? fetch (string key, string? url, string? email, Cancellable job, int minimum_size) {
            var existing = entries.lookup (key);
            if (existing != null && (!existing.ready || existing.expires > get_real_time () / 1000000)) {
                if (!existing.ready) {
                    ulong handler = existing.notify["ready"].connect (() => fetch.callback ());
                    yield;
                    existing.disconnect (handler);
                }
                return sufficient_size (existing.texture, minimum_size);
            }
            if (entries.size () >= 256) { entries.remove_all (); }
            var entry = new AvatarEntry ();
            entries.insert (key, entry);
            try {
                if (email != null) {
                    entry.texture = yield contact_photo (email, job);
                } else {
                    string filename = Path.build_filename (directory, Checksum.compute_for_string (ChecksumType.SHA256, "native-v2-" + key) + ".png");
                    var file = File.new_for_path (filename);
                    try {
                        var info = yield file.query_info_async (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE, Priority.DEFAULT, job);
                        if ((int64) info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED) + 604800 > get_real_time () / 1000000) {
                            uint8[] cached;
                            yield file.load_contents_async (job, out cached, null);
                            entry.texture = decode (new Bytes (cached), true, false, key.has_prefix ("companyenrich-"));
                        }
                    } catch (Error error) { }
                    if (entry.texture == null && !job.is_cancelled ()) {
                        entry.texture = yield download (key, url, job);
                        if (entry.texture != null && !job.is_cancelled ()) {
                            DirUtils.create_with_parents (directory, 0700);
                            var png = entry.texture.save_to_png_bytes ();
                            yield file.replace_contents_async (png.get_data (), null, false, FileCreateFlags.PRIVATE, job, null);
                        }
                    }
                }
            } catch (Error error) { }
            entry.expires = get_real_time () / 1000000 + (email != null ? 300 : entry.texture == null ? 3600 : 86400);
            entry.ready = true;
            return sufficient_size (entry.texture, minimum_size);
        }

        private Gdk.Texture? sufficient_size (Gdk.Texture? texture, int minimum_size) {
            return texture != null && texture.width >= minimum_size && texture.height >= minimum_size ? texture : null;
        }

        private async Gdk.Texture? download (string key, string url, Cancellable job) throws Error {
            bool anylogo = key.has_prefix ("anylogo-");
            bool companyenrich = key.has_prefix ("companyenrich-");
            if ((anylogo && anylogo_retry_after > get_monotonic_time ()) ||
                (companyenrich && company_retry_after > get_monotonic_time ())) { return null; }
            var request = new Soup.Message ("GET", url);
            var stream = yield session.send_async (request, Priority.DEFAULT, job);
            if (request.status_code == 429) {
                if (anylogo) { anylogo_retry_after = get_monotonic_time () + 60000000; }
                if (companyenrich) { company_retry_after = get_monotonic_time () + 60000000; }
            }
            if (request.status_code != 200 ||
                (anylogo && request.response_headers.get_one ("X-Anylogo-Fallback") != null)) {
                yield stream.close_async (Priority.DEFAULT, null);
                return null;
            }
            var bytes = new ByteArray ();
            while (true) {
                var chunk = yield stream.read_bytes_async (16384, Priority.DEFAULT, job);
                if (chunk.get_size () == 0) { break; }
                bytes.append (chunk.get_data ());
                if (bytes.len > 2 * 1024 * 1024) { break; }
            }
            yield stream.close_async (Priority.DEFAULT, null);
            if (bytes.len > 2 * 1024 * 1024) { return null; }
            bool vector = request.response_headers.get_content_type (null) == "image/svg+xml";
            return decode (ByteArray.free_to_bytes ((owned) bytes), true, vector, companyenrich);
        }

        /* ----- CompanyEnrich Generated Placeholders ----- */
        private bool is_generated_monogram (Gdk.Pixbuf image) {
            if (image.width != 128 || image.height != 128) { return false; }
            unowned uint8[] pixels = image.get_pixels ();
            bool has_letters = false;
            for (int y = 0; y < 128; y++) {
                for (int x = 0; x < 128; x++) {
                    int offset = y * image.rowstride + x * image.n_channels;
                    uint8 shade = pixels[offset];
                    if (pixels[offset + 1] != shade || pixels[offset + 2] != shade || shade > 221 ||
                        (image.has_alpha && pixels[offset + 3] != 255)) { return false; }
                    if (shade == 221) { continue; }
                    if (x < 12 || x > 116 || y < 40 || y > 88) { return false; }
                    has_letters = true;
                }
            }
            return has_letters;
        }

        private Gdk.Texture? decode (Bytes bytes, bool strict, bool vector, bool reject_placeholder = false) throws Error {
            bool valid = false;
            var loader = new Gdk.PixbufLoader ();
            loader.size_prepared.connect ((width, height) => {
                valid = width > 0 && height > 0 && width <= 4096 && height <= 4096 &&
                    (!strict || (width == height && (vector || width >= 48)));
                int longest = int.max (width, height);
                int target = vector ? 256 : int.min (256, longest);
                loader.set_size (valid ? int.max (1, width * target / longest) : 1,
                    valid ? int.max (1, height * target / longest) : 1);
            });
            bool complete = false;
            try { loader.write (bytes.get_data ()); }
            finally {
                try { complete = loader.close (); }
                catch (Error error) { }
            }
            var pixbuf = loader.get_pixbuf ();
            if (!complete || !valid || pixbuf == null ||
                (reject_placeholder && is_generated_monogram (pixbuf))) { return null; }
            return Gdk.Texture.for_pixbuf (pixbuf);
        }
    }
}
