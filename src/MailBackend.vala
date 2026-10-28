/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class MailBackend : Object {
        public signal void folders_loaded (Folder[] accounts, Folder? preferred);
        public signal void failed (string message);
        public bool online { get; private set; }
        public bool is_connecting { get; private set; default = true; }
        private bool discovering = true;
        private NetworkMonitor monitor = NetworkMonitor.get_default ();
        private ulong network_handler;
        public uint pending_operations { get; private set; }
        private bool close_requested;
        private HashTable<Message, bool> loading_conversations = new HashTable<Message, bool> (direct_hash, direct_equal);
        private signal void conversation_ready (Message message);
        private HashTable<string, bool> hidden_messages = new HashTable<string, bool> (str_hash, str_equal);
        private HashTable<string, Camel.Transport> transports = new HashTable<string, Camel.Transport> (str_hash, str_equal);
        private HashTable<string, Folder> accounts = new HashTable<string, Folder> (str_hash, str_equal);
        private MailSession session = new MailSession ();
        private Cancellable lifetime = new Cancellable ();
        private HashTable<string, Camel.Store> stores = new HashTable<string, Camel.Store> (str_hash, str_equal);
        private HashTable<string, Camel.Folder> opened = new HashTable<string, Camel.Folder> (str_hash, str_equal);
        private HashTable<Conversation, GenericArray<Camel.MessageInfo>> threads = new HashTable<Conversation, GenericArray<Camel.MessageInfo>> (direct_hash, direct_equal);
        private HashTable<Conversation, Camel.Folder> origins = new HashTable<Conversation, Camel.Folder> (direct_hash, direct_equal);

        private MailCache cache = new MailCache ();
        private HashTable<string, bool> connected = new HashTable<string, bool> (str_hash, str_equal);
        private HashTable<string, string> connection_errors = new HashTable<string, string> (str_hash, str_equal);
        private HashTable<string, Folder> opened_models = new HashTable<string, Folder> (str_hash, str_equal);
        private signal void account_ready (string id);
        public signal void folders_updated (Folder account, Folder[] children);

        public MailBackend () {
            network_handler = monitor.network_changed.connect (queue_connection_update);
            update_connection_state ();
        }

        private void queue_connection_update () {
            Idle.add (() => { update_connection_state (); return Source.REMOVE; });
        }

        private void update_connection_state () {
            bool available = monitor.get_network_available ();
            bool active = false, pending = false;
            foreach (var store in stores.get_values ()) {
                active |= store.connection_status == Camel.ServiceConnectionStatus.CONNECTED;
                pending |= store.connection_status == Camel.ServiceConnectionStatus.CONNECTING;
            }
            online = available && active;
            is_connecting = available && (pending || (discovering && !active));
        }

        protected override void dispose () {
            if (network_handler != 0) { monitor.disconnect (network_handler); network_handler = 0; }
            base.dispose ();
        }

        /* ----- Account and Folder Discovery ----- */
        public async void start () throws Error {
            try {
                yield session.start (lifetime);
                var accounts = new GenericArray<Folder> ();
                Folder? preferred = null;
                foreach (var source in session.registry.list_enabled (E.SOURCE_EXTENSION_MAIL_ACCOUNT)) {
                    var collection = session.registry.find_extension (source, E.SOURCE_EXTENSION_GOA);
                    if (collection == null) { continue; }
                    unowned var goa = (E.SourceGoa) collection.get_extension (E.SOURCE_EXTENSION_GOA);
                    unowned var account = (E.SourceMailAccount) source.get_extension (E.SOURCE_EXTENSION_MAIL_ACCOUNT);
                    var store = session.add_service (source.uid, account.backend_name, Camel.ProviderType.STORE) as Camel.Store;
                    if (store == null) { continue; }
                    (session.registry.find_extension (source, E.SourceCamel.get_extension_name (account.backend_name)) ?? source).camel_configure_service (store);
                    if (account.backend_name == "imapx") {
                        var tuned = store.ref_settings ().clone ();
                        tuned.set ("concurrent-connections", 5u);
                        store.set_settings (tuned);
                    }
                    var root = new Folder (source.display_name, "avatar-default-symbolic", goa.address ?? source.display_name,
                        true, FolderRole.REGULAR, source.uid) { live = true };
                    accounts.add (root);
                    this.accounts.insert (root.id, root);
                    stores.insert (source.uid, store);
                    store.notify["connection-status"].connect (queue_connection_update);
                    cache.restore (root);
                    var inbox = find_inbox (root);
                    if (preferred == null) { preferred = inbox; }
                    if (inbox != null) {
                        try { yield load_local_summary (inbox, lifetime); }
                        catch (Error error) {
                            if (error is IOError.CANCELLED) { throw error; }
                            debug ("Cached Inbox summary is unavailable: %s", error.message);
                        }
                    }
                }
                if (accounts.length == 0) { throw new IOError.NOT_FOUND ("Evolution Data Server has not provided any enabled Online Accounts mail sources."); }
                folders_loaded (accounts.data, preferred);
                bool available = preferred != null;
                foreach (var root in accounts.data) {
                    var store = stores.lookup (root.id);
                    try {
                        if (store is Camel.OfflineStore) { yield ((Camel.OfflineStore) store).set_online (true, Priority.DEFAULT, lifetime); }
                        yield store.connect (Priority.DEFAULT, lifetime);
                        yield configure_special_folders (store);
                            connected.insert (root.id, true);
                        account_ready (root.id);
                        var info = yield store.get_folder_info (null, Camel.StoreGetFolderInfoFlags.RECURSIVE, Priority.DEFAULT, lifetime);
                        var incoming = new Folder (root.name, root.icon_name, root.account, true, FolderRole.REGULAR, root.id);
                        add_folders (info, incoming);
                        var children = new GenericArray<Folder> ();
                        for (uint i = 0; i < incoming.children.get_n_items (); i++) { children.add ((Folder) incoming.children.get_item (i)); }
                        folders_updated (root, children.data);
                        cache.save (root);
                        available |= root.children.get_n_items () > 0;
                        var visited = new GenericArray<Folder> ();
                        foreach (var model in opened_models.get_values ()) {
                            if (root_id (model) == root.id) { visited.add (model); }
                        }
                        foreach (var model in visited.data) {
                            refresh_cached_folder.begin (model);
                        }
                    } catch (Error error) {
                        if (error is IOError.CANCELLED) { throw error; }
                        connection_errors.insert (root.id, error.message);
                        connected.insert (root.id, true);
                        account_ready (root.id);
                        failed ("Unable to refresh account: " + error.message);
                    }
                }
                if (!available) { throw new IOError.NOT_FOUND ("No mail folders are available. Check the connection and try again."); }
            } finally {
                discovering = false;
                update_connection_state ();
            }
        }

        private async void wait_for_connection (Folder model, Cancellable cancellable) throws Error {
            string id = root_id (model);
            if (!connected.contains (id)) {
                bool resumed = false;
                SourceFunc resume = wait_for_connection.callback;
                ulong ready_handler = account_ready.connect ((ready_id) => {
                    if (ready_id == id && !resumed) { resumed = true; resume (); }
                });
                ulong cancel_handler = cancellable.connect (() => {
                    Idle.add (() => {
                        if (!resumed) { resumed = true; resume (); }
                        return Source.REMOVE;
                    });
                });
                yield;
                disconnect (ready_handler);
                cancellable.disconnect (cancel_handler);
            }
            cancellable.set_error_if_cancelled ();
            var error = connection_errors.lookup (id);
            if (error != null) { throw new IOError.NOT_CONNECTED (error); }
        }

        private async void refresh_cached_folder (Folder model) {
            if (model.loading) { return; }
            try { yield load_folder (model, lifetime, true); }
            catch (Error error) {
                if (!(error is IOError.CANCELLED)) { debug ("Background refresh failed: %s", error.message); }
            }
        }

        private void add_folders (Camel.FolderInfo? info, Folder parent) {
            for (unowned Camel.FolderInfo? item = info; item != null; item = item.next) {
                if ((item.flags & Camel.FolderInfoFlags.VIRTUAL) != 0) { continue; }
                FolderRole role = FolderRole.REGULAR;
                switch (folder_flags (stores.lookup (root_id (parent)), item) & Camel.FOLDER_TYPE_MASK) {
                    case Camel.FolderInfoFlags.TYPE_INBOX: role = FolderRole.INBOX; break;
                    case Camel.FolderInfoFlags.TYPE_TRASH: role = FolderRole.TRASH; break;
                    case Camel.FolderInfoFlags.TYPE_JUNK: role = FolderRole.JUNK; break;
                    case Camel.FolderInfoFlags.TYPE_SENT: role = FolderRole.SENT; break;
                    case Camel.FolderInfoFlags.TYPE_DRAFTS: role = FolderRole.DRAFTS; break;
                    case Camel.FolderInfoFlags.TYPE_ARCHIVE: role = FolderRole.ARCHIVE; break;
                    default: break;
                }
                var root = parent;
                while (root.parent != null) { root = root.parent; }
                var folder = new Folder (item.display_name, MailCache.icon_for_role (role), parent.account, false, role, root.id + "/" + item.full_name) {
                    live = true, remote_name = item.full_name,
                    system_folder = role != FolderRole.REGULAR || (item.flags & Camel.FolderInfoFlags.SYSTEM) != 0,
                    selectable = (item.flags & Camel.FolderInfoFlags.NOSELECT) == 0,
                    writable = (item.flags & (Camel.FolderInfoFlags.READONLY | Camel.FolderInfoFlags.VIRTUAL)) == 0,
                    can_create = (item.flags & (Camel.FolderInfoFlags.READONLY | Camel.FolderInfoFlags.NOINFERIORS)) == 0,
                    unread = (uint) int.max (0, item.unread)
                };
                parent.add_child (folder);
                add_folders (item.child, folder);
            }
        }

        private Folder? find_inbox (Folder root) {
            for (uint i = 0; i < root.children.get_n_items (); i++) {
                var folder = (Folder) root.children.get_item (i);
                if (folder.role == FolderRole.INBOX) { return folder; }
                var nested = find_inbox (folder);
                if (nested != null) { return nested; }
            }
            return null;
        }

        /* ----- Conversation Loading ----- */
        public async void load_folder (Folder model, Cancellable cancellable, bool refresh = false) throws Error {
            if (!model.selectable || (!refresh && opened.contains (model.id))) { return; }
            model.loading = true;
            model.error_message = null;
            try {
                if (!opened.contains (model.id)) {
                    try { yield load_local_summary (model, cancellable); }
                    catch (Error error) {
                        if (error is IOError.CANCELLED) { throw error; }
                        debug ("Local folder summary is unavailable: %s", error.message);
                    }
                }
                yield wait_for_connection (model, cancellable);
                var folder = opened.lookup (model.id);
                if (folder == null) { folder = yield stores.lookup (root_id (model)).get_folder (model.remote_name, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable); }
                if (folder == null) { throw new IOError.NOT_FOUND ("The selected folder is no longer available."); }
                yield folder.refresh_info (Priority.DEFAULT, cancellable);
                var batch = yield read_summary (folder, cancellable);
                apply_summary (model, folder, batch);
                cache_account (model);
            } catch (Error error) {
                if (!(error is IOError.CANCELLED)) { model.error_message = error.message; }
                throw error;
            } finally { model.loading = false; }
        }

        private async void load_local_summary (Folder model, Cancellable cancellable) throws Error {
            var folder = yield stores.lookup (root_id (model)).get_folder (model.remote_name, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable);
            if (folder == null) { return; }
            var batch = yield read_summary (folder, cancellable);
            apply_summary (model, folder, batch);
        }

        private async SummaryBatch read_summary (Camel.Folder folder, Cancellable cancellable) throws Error {
            SummaryBatch? batch = null;
            Error? failure = null;
            SourceFunc resume = read_summary.callback;
            new Thread<void*> ("mail-summary", () => {
                try {
                    cancellable.set_error_if_cancelled ();
                    batch = build_summary (folder);
                    cancellable.set_error_if_cancelled ();
                } catch (Error error) { failure = error; }
                Idle.add (() => { resume (); return Source.REMOVE; });
                return null;
            });
            yield;
            cancellable.set_error_if_cancelled ();
            if (failure != null) { throw failure; }
            return batch;
        }

        private SummaryBatch build_summary (Camel.Folder folder) {
            var batch = new SummaryBatch ();
            var uids = new GenericArray<string> ();
            var folder_uids = folder.dup_uids ();
            foreach (var uid in folder_uids.data) { uids.add (uid); }
            var tree = new Camel.FolderThread (folder, uids, Camel.FolderThreadFlags.NONE);
            var conversations = batch.conversations;
            for (unowned Camel.FolderThreadNode? node = tree.get_tree (); node != null; node = node.get_next ()) {
                var members = new GenericArray<Camel.MessageInfo> ();
                collect_messages (node, members);
                if (members.length == 0) { continue; }
                members.sort ((a, b) => compare_time (a.date_sent, b.date_sent));
                var latest = members[members.length - 1];
                bool unread = false, starred = false;
                foreach (var member in members.data) {
                    unread |= (member.flags & Camel.MessageFlags.SEEN) == 0;
                    starred |= (member.flags & Camel.MessageFlags.FLAGGED) != 0;
                }
                var conversation = new Conversation (sender_name (latest.from), latest.subject ?? "(No Subject)",
                    latest.preview ?? "", format_time (latest.date_sent), unread, starred, latest.date_sent) { live = true };
                foreach (var member in members.data) {
                    string name, address;
                    parse_address (member.from, out name, out address);
                    conversation.messages.append (new Message (name, address, member.to ?? "", format_time (member.date_sent), "Loading message…") {
                        uid = member.uid, starred = (member.flags & Camel.MessageFlags.FLAGGED) != 0
                    });
                }
                batch.members.insert (conversation, members);
                conversations.add (conversation);
            }
            conversations.sort ((a, b) => compare_time (b.timestamp, a.timestamp));
            return batch;
        }

        private void apply_summary (Folder model, Camel.Folder folder, SummaryBatch batch) {
            var existing = new HashTable<string, Conversation> (str_hash, str_equal);
            for (uint i = 0; i < model.conversations.get_n_items (); i++) {
                var old = (Conversation) model.conversations.get_item (i);
                existing.insert (conversation_key (old), old);
                threads.remove (old);
                origins.remove (old);
            }
            var shown = new GenericArray<Conversation> ();
            for (uint i = 0; i < batch.conversations.length; i++) {
                var incoming = batch.conversations[i];
                var members = batch.members.lookup (incoming);
                for (int j = (int) members.length - 1; j >= 0; j--) {
                    if (hidden_messages.contains (model.id + "/" + members[(uint) j].uid)) {
                        members.remove_index ((uint) j);
                        incoming.messages.remove ((uint) j);
                    }
                }
                if (members.length == 0) { continue; }
                var retained = existing.lookup (conversation_key (incoming));
                if (retained != null) {
                    retained.unread = incoming.unread;
                    retained.starred = incoming.starred;
                    for (uint j = 0; j < retained.messages.get_n_items (); j++) {
                        ((Message) retained.messages.get_item (j)).starred = ((Message) incoming.messages.get_item (j)).starred;
                    }
                    batch.conversations[i] = retained;
                    incoming = retained;
                }
                threads.insert (incoming, members);
                origins.insert (incoming, folder);
                shown.add (incoming);
            }
            opened.insert (model.id, folder);
            opened_models.insert (model.id, model);
            model.unread = folder.get_folder_summary ().get_unread_count ();
            model.conversations.splice (0, model.conversations.get_n_items (), shown.data);
        }

        private static string conversation_key (Conversation conversation) {
            var key = new StringBuilder ();
            for (uint i = 0; i < conversation.messages.get_n_items (); i++) {
                key.append (((Message) conversation.messages.get_item (i)).uid);
                key.append_c ('/');
            }
            return key.str;
        }

        public void cache_account (Folder model) {
            while (model.parent != null) { model = model.parent; }
            cache.save (model);
        }

        private void collect_messages (Camel.FolderThreadNode node, GenericArray<Camel.MessageInfo> messages) {
            var info = node.get_item () as Camel.MessageInfo;
            if (info != null && (info.flags & Camel.MessageFlags.DELETED) == 0) { messages.add (info); }
            for (unowned Camel.FolderThreadNode? child = node.get_child (); child != null; child = child.get_next ()) {
                collect_messages (child, messages);
            }
        }

        public async void load_conversation (Conversation conversation, Cancellable cancellable, Message? preferred = null) throws Error {
            if (conversation.messages.get_n_items () == 0) { return; }
            var wanted = preferred ?? (Message) conversation.messages.get_item (conversation.messages.get_n_items () - 1);
            if (wanted.loaded) { return; }
            while (loading_conversations.contains (wanted)) {
                bool resumed = false;
                SourceFunc resume = load_conversation.callback;
                ulong ready = conversation_ready.connect ((finished) => {
                    if (finished == wanted && !resumed) { resumed = true; resume (); }
                });
                ulong cancelled = cancellable.connect (() => {
                    Idle.add (() => { if (!resumed) { resumed = true; resume (); } return Source.REMOVE; });
                });
                yield;
                disconnect (ready);
                cancellable.disconnect (cancelled);
                cancellable.set_error_if_cancelled ();
            }
            if (wanted.loaded) { return; }
            loading_conversations.insert (wanted, true);
            try {
                var members = threads.lookup (conversation);
                var folder = origins.lookup (conversation);
                if (members == null || folder == null) { return; }
                for (uint i = 0; i < members.length; i++) {
                    var target = (Message) conversation.messages.get_item (i);
                    if (target != wanted || target.loaded) { continue; }
                    var model = opened_models.lookup (folder.parent_store.uid + "/" + folder.full_name);
                    var mime = yield read_cached_message (folder, members[i].uid, cancellable);
                    if (mime == null) {
                        if (model != null) { yield wait_for_connection (model, cancellable); }
                        mime = yield folder.get_message (members[i].uid, Priority.DEFAULT, cancellable);
                    }
                    if (model != null && model.role == FolderRole.DRAFTS) { target.draft_mime = mime; }
                    target.message_id = mime.get_message_id ();
                    target.reply_to = mime.get_header ("Reply-To");
                    target.cc = mime.get_header ("Cc");
                    target.bcc = mime.get_header ("Bcc");
                    target.in_reply_to = mime.get_header ("In-Reply-To");
                    var body = new MailBody ();
                    yield body.decode (mime.content, cancellable);
                    target.is_html = body.is_html;
                    target.body = body.text ?? "This message has no text content.";
                    target.loaded = true;
                }
            } finally {
                loading_conversations.remove (wanted);
                conversation_ready (wanted);
            }
        }

        private async Camel.MimeMessage? read_cached_message (Camel.Folder folder, string uid, Cancellable cancellable) throws Error {
            Camel.MimeMessage? message = null;
            SourceFunc resume = read_cached_message.callback;
            new Thread<void*> ("mail-cache", () => {
                message = folder.get_message_cached (uid, cancellable);
                Idle.add (() => { resume (); return Source.REMOVE; });
                return null;
            });
            yield;
            cancellable.set_error_if_cancelled ();
            return message;
        }

        /* ----- Server Operations ----- */
        private static string root_id (Folder folder) {
            while (folder.parent != null) { folder = folder.parent; }
            return folder.id;
        }

        public static Camel.FolderInfoFlags folder_flags (Camel.Store store, Camel.FolderInfo info) {
            var flags = info.flags;
            if ((flags & Camel.FOLDER_TYPE_MASK) != Camel.FolderInfoFlags.TYPE_NORMAL) { return flags; }
            var registry = ((MailSession) store.session).registry;
            var source = registry.ref_source (store.uid);
            if (source == null) { return flags; }
            unowned var account = (E.SourceMailAccount) source.get_extension (E.SOURCE_EXTENSION_MAIL_ACCOUNT);
            string uri = "folder://%s/%s".printf (Camel.URL.encode (store.uid, ":;@/"), Camel.URL.encode (info.full_name, ":;@?#"));
            if (account.archive_folder == uri) { return flags | Camel.FolderInfoFlags.TYPE_ARCHIVE; }
            var identity = registry.ref_source (account.identity_uid);
            if (identity != null) {
                unowned var composition = (E.SourceMailComposition) identity.get_extension (E.SOURCE_EXTENSION_MAIL_COMPOSITION);
                unowned var submission = (E.SourceMailSubmission) identity.get_extension (E.SOURCE_EXTENSION_MAIL_SUBMISSION);
                if (composition.drafts_folder == uri) { return flags | Camel.FolderInfoFlags.TYPE_DRAFTS; }
                if (submission.sent_folder == uri) { return flags | Camel.FolderInfoFlags.TYPE_SENT; }
            }
            var settings = store.ref_settings ();
            var klass = (ObjectClass) settings.get_type ().class_ref ();
            if (klass.find_property ("real-trash-path") != null) {
                string? trash, junk;
                settings.get ("real-trash-path", out trash, "real-junk-path", out junk);
                if (info.full_name == trash) { return flags | Camel.FolderInfoFlags.TYPE_TRASH; }
                if (info.full_name == junk) { return flags | Camel.FolderInfoFlags.TYPE_JUNK; }
            }
            switch (info.full_name.casefold ()) {
                case "archive": return flags | Camel.FolderInfoFlags.TYPE_ARCHIVE;
                case "drafts": return flags | Camel.FolderInfoFlags.TYPE_DRAFTS;
                case "sent":
                case "sent messages": return flags | Camel.FolderInfoFlags.TYPE_SENT;
            }
            return flags;
        }

        private async void configure_special_folders (Camel.Store store) throws Error {
            var settings = store.ref_settings ();
            var klass = (ObjectClass) settings.get_type ().class_ref ();
            if (klass.find_property ("real-trash-path") == null) { return; }
            string? trash, junk;
            settings.get ("real-trash-path", out trash, "real-junk-path", out junk);
            if (!string_is_empty (trash) && !string_is_empty (junk)) { return; }
            HashTable<weak string, weak string>? setup;
            if ((yield store.initial_setup (Priority.DEFAULT, lifetime, out setup)) && setup != null) {
                foreach (var kind in new string[] { "trash", "junk" }) {
                    string? current;
                    settings.get ("real-%s-path".printf (kind), out current);
                    var path = setup.lookup ("Backend:Imapx Backend:real-%s-path:s".printf (kind));
                    if (string_is_empty (current) && !string_is_empty (path)) {
                        settings.set ("real-%s-path".printf (kind), path, "use-real-%s-path".printf (kind), true);
                    }
                }
            }
        }

        private static bool string_is_empty (string? value) { return value == null || value == ""; }

        private async Camel.Folder open_folder (Folder model) throws Error {
            yield wait_for_connection (model, lifetime);
            if (!model.selectable || !model.writable) { throw new IOError.PERMISSION_DENIED ("This folder cannot be modified."); }
            var folder = opened.lookup (model.id);
            if (folder == null) { folder = yield stores.lookup (root_id (model)).get_folder (model.remote_name, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, lifetime); }
            if (folder == null) { throw new IOError.NOT_FOUND ("The folder is no longer available."); }
            return folder;
        }

        private void update_flags (Folder model, Conversation[] conversations) {
            foreach (var conversation in conversations) {
                var members = threads.lookup (conversation);
                if (members == null) { continue; }
                bool unread = false, starred = false;
                for (uint i = 0; i < members.length; i++) {
                    unread |= (members[i].flags & Camel.MessageFlags.SEEN) == 0;
                    bool flagged = (members[i].flags & Camel.MessageFlags.FLAGGED) != 0;
                    starred |= flagged;
                    ((Message) conversation.messages.get_item (i)).starred = flagged;
                }
                conversation.unread = unread;
                conversation.starred = starred;
            }
            var folder = opened.lookup (model.id);
            if (folder != null) { model.unread = folder.get_folder_summary ().get_unread_count (); }
            cache_account (model);
        }

        public async void mark (Folder model, owned Conversation[] conversations, string action, Message? single = null) throws Error {
            var folder = yield open_folder (model);
            Camel.MessageFlags mask, value;
            switch (action) {
                case "read": mask = Camel.MessageFlags.SEEN; value = mask; break;
                case "unread": mask = Camel.MessageFlags.SEEN; value = 0; break;
                case "star": mask = Camel.MessageFlags.FLAGGED; value = mask; break;
                case "unstar": mask = Camel.MessageFlags.FLAGGED; value = 0; break;
                default: return;
            }
            folder.freeze ();
            foreach (var conversation in conversations) {
                var members = threads.lookup (conversation);
                if (members == null || origins.lookup (conversation) != folder) { continue; }
                foreach (var info in members.data) {
                    if (single == null || single.uid == info.uid) { info.set_flags (mask, value); }
                }
            }
            folder.thaw ();
            yield folder.synchronize (false, Priority.DEFAULT, lifetime);
            update_flags (model, conversations);
        }

        public void stage_messages (ConversationDrag drag, bool hide) {
            foreach (var conversation in drag.conversations) {
                for (uint i = 0; i < conversation.messages.get_n_items (); i++) {
                    string key = drag.source.id + "/" + ((Message) conversation.messages.get_item (i)).uid;
                    if (hide) { hidden_messages.insert (key, true); } else { hidden_messages.remove (key); }
                }
            }
        }

        public async UndoOperation? move (ConversationDrag drag, Folder destination) throws Error {
            if (root_id (drag.source) != root_id (destination) || drag.source == destination) { throw new IOError.INVALID_ARGUMENT ("Choose another folder in the same account."); }
            var source = yield open_folder (drag.source);
            var target = yield open_folder (destination);
            var uids = new GenericArray<string> ();
            foreach (var conversation in drag.conversations) {
                var members = threads.lookup (conversation);
                if (members == null || origins.lookup (conversation) != source) { throw new IOError.NOT_FOUND ("The selected conversation has changed."); }
                foreach (var info in members.data) { uids.add (info.uid); }
            }
            GenericArray<weak string>? transferred;
            if (!yield source.transfer_messages_to (uids, target, true, Priority.DEFAULT, lifetime, out transferred)) { throw new IOError.FAILED ("The server could not move these messages."); }
            try {
                yield load_folder (drag.source, lifetime, true);
                if (opened.contains (destination.id)) { yield load_folder (destination, lifetime, true); }
            } catch (Error error) { failed ("Messages moved; the view could not be refreshed"); }
            foreach (var conversation in drag.conversations) { threads.remove (conversation); origins.remove (conversation); }
            if (transferred == null || transferred.length != uids.length) { return null; }
            var undo_uids = new GenericArray<string> ();
            foreach (var uid in transferred.data) { undo_uids.add (uid); }
            return new UndoOperation (() => {
                undo_move.begin (drag.source, destination, undo_uids, (obj, result) => {
                    try { undo_move.end (result); } catch (Error error) { failed ("Unable to undo move: " + error.message); }
                });
            });
        }

        private async void undo_move (Folder original, Folder destination, GenericArray<string> uids) throws Error {
            var source = yield open_folder (destination);
            var target = yield open_folder (original);
            yield source.transfer_messages_to (uids, target, true, Priority.DEFAULT, lifetime, null);
            yield load_folder (original, lifetime, true);
            yield load_folder (destination, lifetime, true);
        }

        public async void empty_trash (Folder model) throws Error {
            if (model.role != FolderRole.TRASH) { throw new IOError.PERMISSION_DENIED ("Only Trash can be emptied."); }
            var folder = yield open_folder (model);
            yield BackendTrash.empty (folder, lifetime);
            yield load_folder (model, lifetime, true);
            model.children.remove_all ();
        }

        public async Folder create_folder (Folder parent, string name) throws Error {
            yield wait_for_connection (parent, lifetime);
            if (!parent.can_create || parent.is_in_trash ()) { throw new IOError.PERMISSION_DENIED ("This folder cannot contain subfolders."); }
            var info = yield BackendFolders.create (stores.lookup (root_id (parent)), parent.is_account ? null : parent.remote_name, name, lifetime);
            return new Folder (name, "folder-symbolic", parent.account, false, FolderRole.REGULAR, root_id (parent) + "/" + info.full_name) {
                live = true, remote_name = info.full_name
            };
        }

        public async void rename_folder (Folder model, string name, Folder? destination = null) throws Error {
            yield wait_for_connection (model, lifetime);
            if (model.is_account || model.system_folder || model.role != FolderRole.REGULAR || !model.writable) { throw new IOError.PERMISSION_DENIED ("System folders cannot be renamed or moved."); }
            var store = stores.lookup (root_id (model));
            string path;
            if (destination != null) {
                if (root_id (destination) != root_id (model)) { throw new IOError.PERMISSION_DENIED ("Choose a folder in the same account."); }
                path = yield BackendFolders.move_to_trash (store, model.remote_name, lifetime);
            } else {
                if (!BackendFolders.valid_name (name)) { throw new IOError.INVALID_ARGUMENT ("Choose a valid folder name."); }
                string prefix = model.parent.is_account ? "" : model.parent.remote_name + "/";
                path = prefix + name;
                if (!yield store.rename_folder (model.remote_name, path, Priority.DEFAULT, lifetime)) { throw new IOError.FAILED ("The server could not rename the folder."); }
            }
            update_paths (model, model.remote_name, path);
        }

        private void update_paths (Folder model, string previous, string path) {
            opened.remove (model.id);
            opened_models.remove (model.id);
            model.remote_name = path + model.remote_name.substring (previous.length);
            model.id = root_id (model) + "/" + model.remote_name;
            for (uint i = 0; i < model.children.get_n_items (); i++) { update_paths ((Folder) model.children.get_item (i), previous, path); }
        }

        /* ----- SMTP Submission ----- */
        public async bool send (Folder account, string to, string cc, string bcc, string subject, string html, GenericArray<File> files, string? reply_id, Cancellable cancellable, GenericArray<Camel.MimePart>? preserved = null) throws Error {
            if (subject.contains ("\r") || subject.contains ("\n")) { throw new IOError.INVALID_ARGUMENT ("The subject must be a single line."); }
            yield wait_for_connection (account, cancellable);
            var source = session.registry.ref_source (root_id (account));
            if (source == null) { throw new IOError.NOT_FOUND ("The sending account is no longer available."); }
            unowned var mail = (E.SourceMailAccount) source.get_extension (E.SOURCE_EXTENSION_MAIL_ACCOUNT);
            var identity = session.registry.ref_source (mail.identity_uid);
            if (identity == null) { throw new IOError.NOT_FOUND ("The sending identity is unavailable."); }
            unowned var submission = (E.SourceMailSubmission) identity.get_extension (E.SOURCE_EXTENSION_MAIL_SUBMISSION);
            var transport_source = session.registry.ref_source (submission.transport_uid);
            if (transport_source == null) { throw new IOError.NOT_FOUND ("No outgoing server is configured for this account."); }
            unowned var transport_settings = (E.SourceMailTransport) transport_source.get_extension (E.SOURCE_EXTENSION_MAIL_TRANSPORT);
            var transport = transports.lookup (transport_source.uid);
            if (transport == null) {
                transport = session.add_service (transport_source.uid, transport_settings.backend_name, Camel.ProviderType.TRANSPORT) as Camel.Transport;
                if (transport == null) { throw new IOError.NOT_SUPPORTED ("The outgoing server is not supported."); }
                (session.registry.find_extension (transport_source, E.SourceCamel.get_extension_name (transport_settings.backend_name)) ?? transport_source).camel_configure_service (transport);
                transports.insert (transport_source.uid, transport);
            }
            var prepared = yield prepare_message (account, to, cc, bcc, subject, html, files, reply_id, false, cancellable, preserved);
            var mime = prepared.mime;
            var from = prepared.from;
            var recipients = prepared.recipients;
            if (transport.connection_status != Camel.ServiceConnectionStatus.CONNECTED) { yield transport.connect (Priority.DEFAULT, cancellable); }
            bool saved;
            if (!yield transport.send_to (mime, from, recipients, Priority.DEFAULT, cancellable, out saved)) { throw new IOError.FAILED ("The outgoing server did not accept the message."); }
            if (transport_source.has_extension (E.SOURCE_EXTENSION_AUTHENTICATION)) {
                unowned var auth = (E.SourceAuthentication) transport_source.get_extension (E.SOURCE_EXTENSION_AUTHENTICATION);
                string host = auth.host ?? "";
                saved |= host.has_suffix ("gmail.com") || host.has_suffix ("googlemail.com") || host.has_suffix ("office365.com") || host.has_suffix ("outlook.com");
            }
            if (!saved && (transport.get_provider ().flags & Camel.ProviderFlags.DISABLE_SENT_FOLDER) == 0) {
                try {
                    var sent = yield special_folder (account, FolderRole.SENT, submission.sent_folder, lifetime);
                    var info = Camel.MessageInfo.@new (null);
                    info.set_flags (Camel.MessageFlags.SEEN, Camel.MessageFlags.SEEN);
                    saved = yield sent.append_message (mime, info, Priority.DEFAULT, null, null);
                } catch (Error error) { debug ("Unable to save sent copy: %s", error.message); }
            }
            return saved;
        }

        /* ----- Drafts and Special Folders ----- */
        private async PreparedMessage prepare_message (Folder account, string to, string cc, string bcc, string subject, string html, GenericArray<File> files, string? reply_id, bool draft, Cancellable cancellable, GenericArray<Camel.MimePart>? preserved = null) throws Error {
            var source = session.registry.ref_source (root_id (account));
            if (source == null) { throw new IOError.NOT_FOUND ("The account is no longer available."); }
            unowned var mail = (E.SourceMailAccount) source.get_extension (E.SOURCE_EXTENSION_MAIL_ACCOUNT);
            var identity = session.registry.ref_source (mail.identity_uid);
            if (identity == null) { throw new IOError.NOT_FOUND ("The sending identity is unavailable."); }
            var mime = new Camel.MimeMessage ();
            var from = new Camel.InternetAddress ();
            unowned var sender = (E.SourceMailIdentity) identity.get_extension (E.SOURCE_EXTENSION_MAIL_IDENTITY);
            from.add (sender.name, account.account);
            mime.set_from (from);
            mime.set_subject (subject);
            mime.set_date (Camel.MESSAGE_DATE_CURRENT, 0);
            mime.set_message_id (null);
            if (!string_is_empty (reply_id)) {
                string reference = reply_id.strip ();
                if (!reference.has_prefix ("<")) { reference = "<" + reference + ">"; }
                mime.set_header ("In-Reply-To", reference);
                mime.set_header ("References", reference);
            }
            var recipients = new Camel.InternetAddress ();
            string[] fields = { to, cc, bcc };
            string[] kinds = { Camel.RECIPIENT_TYPE_TO, Camel.RECIPIENT_TYPE_CC, Camel.RECIPIENT_TYPE_BCC };
            for (int i = 0; i < fields.length; i++) {
                if (fields[i].strip () == "") { continue; }
                if (fields[i].contains ("\r") || fields[i].contains ("\n")) { throw new IOError.INVALID_ARGUMENT ("Enter valid email addresses."); }
                var parsed = new Camel.InternetAddress ();
                if (parsed.decode (fields[i]) <= 0 && !draft) { throw new IOError.INVALID_ARGUMENT ("Enter valid email addresses."); }
                for (int j = 0; j < parsed.length (); j++) {
                    unowned string? name, address;
                    parsed.get (j, out name, out address);
                    if (!draft && (address == null || !address.contains ("@"))) { throw new IOError.INVALID_ARGUMENT ("Enter valid email addresses."); }
                }
                recipients.cat (parsed);
                if (draft) { mime.set_header (kinds[i], fields[i]); }
                else if (i < 2) { mime.set_recipients (kinds[i], parsed); }
            }
            if (!draft && recipients.length () == 0) { throw new IOError.INVALID_ARGUMENT ("Add at least one recipient."); }
            var body = new Camel.MimePart ();
            body.set_content (html.data, "text/html; charset=UTF-8");
            body.set_encoding (Camel.TransferEncoding.ENCODING_QUOTEDPRINTABLE);
            var multipart = new Camel.Multipart ();
            multipart.set_mime_type ("multipart/mixed");
            multipart.set_boundary (null);
            multipart.add_part (body);
            foreach (var file in files.data) {
                uint8[] contents;
                yield file.load_contents_async (cancellable, out contents, null);
                var part = new Camel.MimePart ();
                var type = ContentType.guess (file.get_basename (), contents, null);
                part.set_content (contents, ContentType.get_mime_type (type));
                part.set_filename (file.get_basename ());
                part.set_disposition ("attachment");
                part.set_encoding (Camel.TransferEncoding.ENCODING_BASE64);
                multipart.add_part (part);
            }
            if (preserved != null) { foreach (var part in preserved.data) { multipart.add_part (part); } }
            mime.content = multipart;
            return new PreparedMessage (mime, from, recipients);
        }

        private Folder? find_role (Folder parent, FolderRole role) {
            string path = parent.remote_name.casefold ();
            bool named = role == FolderRole.DRAFTS && path == "drafts"
                || role == FolderRole.SENT && (path == "sent" || path == "sent messages")
                || role == FolderRole.ARCHIVE && path == "archive";
            if ((parent.role == role || named) && parent.selectable && parent.writable && !parent.is_account) { return parent; }
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var found = find_role ((Folder) parent.children.get_item (i), role);
                if (found != null) { return found; }
            }
            return null;
        }

        private async Camel.Folder special_folder (Folder account, FolderRole role, string? uri, Cancellable cancellable) throws Error {
            var store = stores.lookup (root_id (account));
            string? path = null;
            string prefix = "folder://" + Camel.URL.encode (store.uid, ":;@/") + "/";
            if (uri != null && uri.has_prefix (prefix)) { path = Uri.unescape_string (uri.substring (prefix.length)); }
            if (path == null) {
                var target = find_role (accounts.lookup (store.uid), role);
                if (target != null) { path = target.remote_name; }
            }
            if (path == null) { throw new IOError.NOT_FOUND ("The account's %s folder is unavailable.".printf (role == FolderRole.DRAFTS ? "Drafts" : "Sent")); }
            var folder = yield store.get_folder (path, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable);
            if (folder == null) { throw new IOError.NOT_FOUND ("The server folder is unavailable."); }
            return folder;
        }

        public async void save_draft (ComposeSnapshot snapshot, Cancellable cancellable) throws Error {
            var prepared = yield prepare_message (snapshot.account, snapshot.to, snapshot.cc, snapshot.bcc, snapshot.subject, snapshot.html, snapshot.files, snapshot.reply_id, true, cancellable, snapshot.parts);
            yield wait_for_connection (snapshot.account, cancellable);
            var folder = yield special_folder (snapshot.account, FolderRole.DRAFTS, null, cancellable);
            var info = Camel.MessageInfo.@new (null);
            info.set_flags (Camel.MessageFlags.DRAFT | Camel.MessageFlags.SEEN, Camel.MessageFlags.DRAFT | Camel.MessageFlags.SEEN);
            if (!yield folder.append_message (prepared.mime, info, Priority.DEFAULT, cancellable, null)) { throw new IOError.FAILED ("The server could not save this draft."); }
            try { yield discard_previous_draft (snapshot, cancellable); }
            catch (Error error) { failed ("Draft saved; the previous version could not be removed"); }
            var model = find_role (accounts.lookup (root_id (snapshot.account)), FolderRole.DRAFTS);
            if (model != null) { refresh_cached_folder.begin (model); }
        }

        public async void discard_previous_draft (ComposeSnapshot snapshot, Cancellable cancellable) throws Error {
            if (snapshot.draft_uid == null) { return; }
            var original_account = snapshot.draft_account ?? snapshot.account;
            yield wait_for_connection (original_account, cancellable);
            var folder = yield special_folder (original_account, FolderRole.DRAFTS, null, cancellable);
            var info = folder.get_message_info (snapshot.draft_uid);
            if (info != null) { info.set_flags (Camel.MessageFlags.DELETED, Camel.MessageFlags.DELETED); }
            yield folder.synchronize (false, Priority.DEFAULT, cancellable);
            var model = find_role (accounts.lookup (root_id (original_account)), FolderRole.DRAFTS);
            if (model != null) { refresh_cached_folder.begin (model); }
        }

        public void begin_background () {
            GLib.Application.get_default ().hold ();
            pending_operations++;
        }

        public void end_background () {
            pending_operations--;
            if (pending_operations == 0 && close_requested) {
                bool visible_window = false;
                foreach (var window in ((Gtk.Application) GLib.Application.get_default ()).get_windows ()) { visible_window |= window.visible; }
                if (!visible_window) { lifetime.cancel (); }
            }
            GLib.Application.get_default ().release ();
        }

        public void cancel () {
            close_requested = true;
            if (pending_operations == 0) { lifetime.cancel (); }
        }

        private static int compare_time (int64 a, int64 b) { return a < b ? -1 : a > b ? 1 : 0; }
        private static string format_time (int64 timestamp) { return new DateTime.from_unix_local (timestamp).format ("%b %e, %H:%M"); }
        private static string sender_name (string? from) {
            string name, address;
            parse_address (from, out name, out address);
            return name;
        }
        private static void parse_address (string? from, out string name, out string address) {
            var parsed = new Camel.InternetAddress ();
            name = from ?? "Unknown Sender";
            address = "";
            if (from != null && parsed.decode (from) > 0) {
                unowned string? display, email;
                if (parsed.get (0, out display, out email)) { name = display ?? email ?? name; address = email ?? ""; }
            }
        }
    }

    internal class PreparedMessage : Object {
        public Camel.MimeMessage mime;
        public Camel.InternetAddress from;
        public Camel.InternetAddress recipients;
        public PreparedMessage (Camel.MimeMessage mime, Camel.InternetAddress from, Camel.InternetAddress recipients) {
            this.mime = mime; this.from = from; this.recipients = recipients;
        }
    }

    internal class SummaryBatch : Object {
        public GenericArray<Conversation> conversations = new GenericArray<Conversation> ();
        public HashTable<Conversation, GenericArray<Camel.MessageInfo>> members = new HashTable<Conversation, GenericArray<Camel.MessageInfo>> (direct_hash, direct_equal);
    }

    /* ----- MIME Text Decoding ----- */
    internal class MailBody : Object {
        public string? text;
        public bool is_html;
        public async void decode (Camel.DataWrapper content, Cancellable cancellable) throws Error {
            var multipart = content as Camel.Multipart;
            if (multipart != null) {
                for (uint i = 0; i < multipart.get_number (); i++) {
                    var part = multipart.get_part (i);
                    if (part.get_disposition () == "attachment") { continue; }
                    yield decode (part.content, cancellable);
                }
                return;
            }
            var type = content.get_mime_type_field ();
            if (type.type != "text" || (type.subtype != "plain" && type.subtype != "html") || (text != null && is_html)) { return; }
            var stream = new MemoryOutputStream.resizable ();
            yield content.decode_to_output_stream (stream, Priority.DEFAULT, cancellable);
            stream.close ();
            var bytes = stream.steal_as_bytes ();
            if (bytes.get_size () == 0) { text = ""; return; }
            var raw = (string) bytes.get_data ();
            var encoding = type.param ("charset") ?? "UTF-8";
            try { text = GLib.convert (raw, (ssize_t) bytes.get_size (), "UTF-8", encoding); }
            catch (ConvertError error) { text = raw.make_valid ((ssize_t) bytes.get_size ()); }
            is_html = type.subtype == "html";
        }
    }
}
