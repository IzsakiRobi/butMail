/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace Mail {
    public class AvatarImage : Object {
        public Gdk.Pixbuf image;
        public string source;
        public AvatarImage (Gdk.Pixbuf image, string source) { this.image = image; this.source = source; }
    }

    private class AvatarEntry : Object {
        public Gdk.Pixbuf? texture;
        public bool ready { get; set; }
        public int64 expires;
    }

    public class AvatarStore : Object {
        public signal void changed ();
        private Settings settings;
        private Soup.Session session;
        private HashTable<string, AvatarEntry> entries = new HashTable<string, AvatarEntry> (str_hash, str_equal);
        private static AvatarStore? instance;
        private Cancellable cancellable = new Cancellable ();
        private uint generation;
        private int64 anylogo_retry_after;
        private int64 company_retry_after;
        private bool pruning;
        private uint writes;
        private string directory = Path.build_filename (Environment.get_user_cache_dir (), APPLICATION_ID, "avatars-v4");

        public AvatarStore (Settings settings) {
            this.settings = settings;
            session = (Soup.Session) Object.new (typeof (Soup.Session), "timeout", 8u,
                "max-conns", 4, "max-conns-per-host", 4, "user-agent", "butMail");
            settings.changed["load-remote-avatars"].connect (invalidate);
            settings.changed["show-avatars"].connect (invalidate);
            LogoCredentials.get_default ().changed.connect (invalidate);
            ContactManager.get_default ().avatars_changed.connect (invalidate);
            prune_cache.begin ();
        }

        private void invalidate () {
            generation++;
            cancellable.cancel ();
            cancellable = new Cancellable ();
            entries.remove_all ();
            changed ();
        }

        public static unowned AvatarStore get_default () {
            if (instance == null) { instance = new AvatarStore (Application.settings); }
            return instance;
        }

        private async Gdk.Pixbuf? contact_photo (string email, Cancellable job) {
            var icon = yield ContactManager.get_default ().lookup_avatar (email);
            if (icon == null || job.is_cancelled ()) { return null; }
            try {
                var stream = yield icon.load_async (256, job);
                try {
                    var image = yield new Gdk.Pixbuf.from_stream_async (stream, job);
                    int edge = int.max (image.width, image.height);
                    return edge <= 256 ? image : image.scale_simple (int.max (1, image.width * 256 / edge),
                        int.max (1, image.height * 256 / edge), Gdk.InterpType.BILINEAR);
                }
                finally { close_stream (stream); }
            } catch (Error error) { return null; }
        }

        /* ----- Ordered Avatar Sources ----- */
        public async AvatarImage? lookup (string address, int minimum_size) {
            string email = address.strip ().down ();
            int separator = email.last_index_of ("@");
            if (separator <= 0 || !settings.get_boolean ("show-avatars") || !settings.get_boolean ("load-remote-avatars")) { return null; }
            uint version = generation;
            var job = cancellable;
            string hash = Checksum.compute_for_string (ChecksumType.SHA256, email);
            var contact = yield fetch ("contact-" + hash, null, email, job, minimum_size);
            if (version != generation || job.is_cancelled ()) { return null; }
            if (contact != null) { return new AvatarImage (contact, _("Photo from your address book")); }
            var image = yield fetch ("gravatar-" + hash,
                "https://www.gravatar.com/avatar/" + hash + "?s=256&d=404&r=g", null, job, minimum_size);
            if (version != generation || job.is_cancelled ()) { return null; }
            if (image != null) { return new AvatarImage (image, _("Avatar from Gravatar")); }
            string domain = Hostname.to_ascii (email.substring (separator + 1)) ?? "";
            if (!Regex.match_simple ("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,63}$", domain)) { return null; }
            try { domain = Soup.tld_get_base_domain (domain); }
            catch (Error error) { return null; }
            var credentials = LogoCredentials.get_default ();
            yield credentials.ensure_ready ();
            if (version != generation || job.is_cancelled ()) { return null; }
            string source = _("Logo from Logo.dev");
            if (credentials.key != null && credentials.key != "") {
                string token = credentials.key;
                string key_hash = Checksum.compute_for_string (ChecksumType.SHA256, token);
                image = yield fetch ("logodev-" + domain + "-" + key_hash,
                    "https://img.logo.dev/" + domain + "?size=256&format=png&fallback=404&token=" + Uri.escape_string (token), null, job, minimum_size);
            }
            if (version != generation || job.is_cancelled ()) { return null; }
            if (image == null) {
                source = _("Logo from AnyLogo");
                image = yield fetch ("anylogo-" + domain,
                    "https://img.anylogo.dev/" + domain + "?size=256&fallback=404", null, job, minimum_size);
            }
            if (version != generation || job.is_cancelled ()) { return null; }
            if (image == null) {
                source = _("Logo from CompanyEnrich");
                string company_domain = domain == "firefox.com" ? "Firefox.com" : domain;
                image = yield fetch ("companyenrich-" + company_domain,
                    "https://api.companyenrich.com/logo/" + company_domain, null, job, minimum_size);
            }
            return version == generation && !job.is_cancelled () && image != null ? new AvatarImage (image, source) : null;
        }

        /* ----- Shared Requests and Cache ----- */
        private async Gdk.Pixbuf? fetch (string key, string? url, string? email, Cancellable job, int minimum_size) {
            string cache_key = key + "-min%d".printf (minimum_size);
            var existing = entries.lookup (cache_key);
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
            entries.insert (cache_key, entry);
            try {
                if (email != null) {
                    entry.texture = yield contact_photo (email, job);
                } else {
                    string filename = Path.build_filename (directory, Checksum.compute_for_string (ChecksumType.SHA256, "native-v3-" + cache_key) + ".png");
                    var file = File.new_for_path (filename);
                    try {
                        var info = yield file.query_info_async (FileAttribute.TIME_MODIFIED + "," + FileAttribute.STANDARD_SIZE,
                            FileQueryInfoFlags.NONE, Priority.DEFAULT, job);
                        if (info.get_size () <= 2 * 1024 * 1024 &&
                            (int64) info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED) + 604800 > get_real_time () / 1000000) {
                            uint8[] cached;
                            yield file.load_contents_async (job, out cached, null);
                            entry.texture = decode (new Bytes (cached), true, false, key.has_prefix ("companyenrich-"));
                        }
                    } catch (Error error) { }
                    if (entry.texture == null && !job.is_cancelled ()) {
                        entry.texture = yield download (key, url, job);
                        if (entry.texture != null && !job.is_cancelled ()) {
                            DirUtils.create_with_parents (directory, 0700);
                            uint8[] png;
                            entry.texture.save_to_buffer (out png, "png");
                            yield file.replace_contents_async (png, null, false, FileCreateFlags.PRIVATE, job, null);
                            if (job.is_cancelled ()) { yield file.delete_async (Priority.DEFAULT, null); entry.texture = null; }
                            if (++writes % 64 == 0) { prune_cache.begin (); }
                        }
                    }
                }
            } catch (Error error) { }
            if (job.is_cancelled ()) { entry.texture = null; }
            entry.expires = get_real_time () / 1000000 + (email != null ? 300 : entry.texture == null ? 3600 : 86400);
            entry.ready = true;
            return sufficient_size (entry.texture, minimum_size);
        }

        private Gdk.Pixbuf? sufficient_size (Gdk.Pixbuf? texture, int minimum_size) {
            return texture != null && texture.width >= minimum_size && texture.height >= minimum_size ? texture : null;
        }

        private static void close_stream (InputStream stream) {
            stream.close_async.begin (Priority.DEFAULT, null, (obj, result) => {
                try { stream.close_async.end (result); } catch (Error error) { }
            });
        }

        private static void close_files (FileEnumerator files) {
            files.close_async.begin (Priority.DEFAULT, null, (obj, result) => {
                try { files.close_async.end (result); } catch (Error error) { }
            });
        }

        private async void prune_cache () {
            if (pruning) { return; }
            pruning = true;
            try {
                var root = File.new_for_path (directory);
                var files = yield root.enumerate_children_async (
                    FileAttribute.STANDARD_NAME + "," + FileAttribute.TIME_MODIFIED,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, null);
                var images = new Gee.ArrayList<FileInfo> ();
                try {
                    while (true) {
                        var batch = yield files.next_files_async (64, Priority.LOW, null);
                        if (batch == null) { break; }
                        foreach (var info in batch) {
                            if (Regex.match_simple ("^[a-f0-9]{64}\\.png$", info.get_name ())) { images.add (info); }
                        }
                    }
                } finally { close_files (files); }
                images.sort ((a, b) => {
                    uint64 first = a.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
                    uint64 second = b.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
                    return first < second ? -1 : first > second ? 1 : 0;
                });
                for (int i = 0; i < images.size; i++) {
                    var info = images[i];
                    if (i < images.size - 512 || (int64) info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED) + 604800 < get_real_time () / 1000000) {
                        try { yield root.get_child (info.get_name ()).delete_async (Priority.LOW, null); }
                        catch (IOError.NOT_FOUND error) { }
                    }
                }
            } catch (Error error) { }
            finally { pruning = false; }
        }

        public async void clear_cache () throws Error {
            generation++;
            cancellable.cancel ();
            cancellable = new Cancellable ();
            entries.remove_all ();
            try {
                var root = File.new_for_path (directory);
                FileEnumerator files;
                try {
                    files = yield root.enumerate_children_async (FileAttribute.STANDARD_NAME,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
                } catch (IOError.NOT_FOUND error) { return; }
                try {
                    while (true) {
                        var batch = yield files.next_files_async (32, Priority.DEFAULT, null);
                        if (batch == null) { break; }
                        foreach (var info in batch) {
                            if (Regex.match_simple ("^[a-f0-9]{64}\\.png$", info.get_name ())) {
                                try { yield root.get_child (info.get_name ()).delete_async (Priority.DEFAULT, null); }
                                catch (IOError.NOT_FOUND error) { }
                            }
                        }
                    }
                } finally { close_files (files); }
            } finally { changed (); }
        }

        /* ----- Logo Presentation ----- */
        public Gdk.Pixbuf frame_image (Gdk.Pixbuf image, int logical_size) {
            bool transparent;
            if (has_filled_background (image, out transparent)) { return image; }
            int edge = int.max (image.width, image.height);
            int inset = int.max (1, (edge * 4 + logical_size / 2) / logical_size);
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, edge, edge);
            var cr = new Cairo.Context (surface);
            if (transparent) {
                var gradient = new Cairo.Pattern.linear (0, 0, 0, edge);
                gradient.add_color_stop_rgb (0, 1, 1, 1);
                gradient.add_color_stop_rgb (1, 0.91, 0.92, 0.93);
                cr.set_source (gradient);
            } else { cr.set_source_rgb (1, 1, 1); }
            cr.paint ();
            double scale = (double) (edge - 2 * inset) / edge;
            cr.translate ((edge - image.width * scale) / 2, (edge - image.height * scale) / 2);
            cr.scale (scale, scale);
            Gdk.cairo_set_source_pixbuf (cr, image, 0, 0);
            cr.paint ();
            return Gdk.pixbuf_get_from_surface (surface, 0, 0, edge, edge) ?? image;
        }

        private bool has_filled_background (Gdk.Pixbuf image, out bool transparent) {
            unowned uint8[] pixels = image.get_pixels ();
            int filled = 0;
            transparent = false;
            int edge_x = int.max (1, image.width * 3 / 100);
            int edge_y = int.max (1, image.height * 3 / 100);
            for (int side = 0; side < 4; side++) {
                for (int step = 1; step <= 3; step++) {
                    int x = side < 2 ? (image.width - 1) * step / 4 :
                        side == 2 ? edge_x : image.width - 1 - edge_x;
                    int y = side < 2 ? (side == 0 ? edge_y : image.height - 1 - edge_y) :
                        (image.height - 1) * step / 4;
                    int offset = y * image.rowstride + x * image.n_channels;
                    bool opaque = !image.has_alpha || pixels[offset + 3] >= 250;
                    bool colored = pixels[offset] < 240 || pixels[offset + 1] < 240 || pixels[offset + 2] < 240;
                    if (!opaque) { transparent = true; }
                    if (opaque && colored) { filled++; }
                }
            }
            return filled >= 8;
        }

        private async Gdk.Pixbuf? download (string key, string url, Cancellable job) throws Error {
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

        private Gdk.Pixbuf? decode (Bytes bytes, bool strict, bool vector, bool reject_placeholder = false) throws Error {
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
            if (strict && pixbuf.has_alpha) {
                unowned uint8[] pixels = pixbuf.get_pixels ();
                bool visible = false;
                for (int y = 0; y < pixbuf.height && !visible; y++) {
                    for (int x = 0; x < pixbuf.width; x++) {
                        if (pixels[y * pixbuf.rowstride + x * pixbuf.n_channels + 3] > 0) {
                            visible = true;
                            break;
                        }
                    }
                }
                if (!visible) { return null; }
            }
            return pixbuf;
        }
    }
}
