/*
 * Copyright 2021 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
namespace ButMail {
    private class InboxItem : Object {
        public string uid;
        public string sender;
        public string subject;
        public bool unread;

        public InboxItem (Camel.MessageInfo info) {
            uid = info.uid;
            sender = info.from ?? "Unknown Sender";
            subject = info.subject ?? "(No Subject)";
            unread = (info.flags & (Camel.MessageFlags.SEEN | Camel.MessageFlags.DELETED)) == 0;
        }
    }

    private class InboxWatch : Object {
        public Folder model;
        public Camel.Folder folder;
        public ulong handler;
        public bool ready;
        public bool scanning;
        public bool dirty;
        public uint unread;
        public HashTable<string, bool> known = new HashTable<string, bool> (str_hash, str_equal);
        public HashTable<string, bool> hidden = new HashTable<string, bool> (str_hash, str_equal);

        public InboxWatch (Folder model, Camel.Folder folder) {
            this.model = model;
            this.folder = folder;
        }
    }

    public class InboxMonitor : Object {
        public signal void mail_arrived (Folder folder);
        private weak Application app;
        private weak MailBackend backend;
        private HashTable<string, InboxWatch> inboxes = new HashTable<string, InboxWatch> (str_hash, str_equal);
        private NotificationTracker notifications;
        private uint poll;
        private uint dock_watch;
        private bool stopped;

        public InboxMonitor (Application app, MailBackend backend) {
            this.app = app;
            this.backend = backend;
            notifications = new NotificationTracker (Path.build_filename (Environment.get_user_data_dir (), Application.ID, "notifications.gv"));
            notifications.withdrawal_requested.connect ((id) => app.withdraw_notification (id));
            backend.inbox_ready.connect (watch);
            backend.messages_staged.connect (stage);
            poll = Timeout.add_seconds (60, () => {
                backend.refresh_inboxes.begin ();
                return Source.CONTINUE;
            });
            dock_watch = Bus.watch_name_on_connection (app.get_dbus_connection (), "com.canonical.Unity",
                BusNameWatcherFlags.NONE, () => update_badge (), null);
        }

        /* ----- Inbox Changes ----- */
        private void watch (Folder model, Camel.Folder folder) {
            if (stopped || inboxes.contains (model.id)) { return; }
            var inbox = new InboxWatch (model, folder);
            inboxes.insert (model.id, inbox);
            inbox.handler = folder.changed.connect (() => {
                Idle.add (() => {
                    if (!stopped) { scan.begin (inbox); }
                    return Source.REMOVE;
                });
            });
            scan.begin (inbox);
        }

        private async GenericArray<InboxItem> snapshot (Camel.Folder folder) {
            var items = new GenericArray<InboxItem> ();
            SourceFunc resume = snapshot.callback;
            new Thread<void*> ("inbox-notifications", () => {
                var uids = folder.dup_uids ();
                foreach (var uid in uids.data) {
                    var info = folder.get_message_info (uid);
                    if (info != null) { items.add (new InboxItem (info)); }
                }
                Idle.add (() => { resume (); return Source.REMOVE; });
                return null;
            });
            yield;
            return items;
        }

        private async void scan (InboxWatch inbox) {
            inbox.dirty = true;
            if (inbox.scanning || stopped) { return; }
            inbox.scanning = true;
            do {
                inbox.dirty = false;
                var items = yield snapshot (inbox.folder);
                if (stopped) { break; }
                bool arrived = false;
                var present = new HashTable<string, bool> (str_hash, str_equal);
                var unread = new HashTable<string, bool> (str_hash, str_equal);
                foreach (var item in items.data) {
                    present.insert (item.uid, true);
                    if (!item.unread || inbox.hidden.contains (item.uid)) { continue; }
                    unread.insert (item.uid, true);
                    if (inbox.ready && !inbox.known.contains (item.uid)) {
                        notify_message (inbox.model, item);
                        arrived = true;
                    }
                }
                notifications.resolve (inbox.model.id, unread);
                notifications.save ();
                inbox.known = present;
                inbox.ready = true;
                inbox.unread = unread.size ();
                if (arrived) { mail_arrived (inbox.model); }
                update_badge ();
                yield backend.update_folder_view (inbox.model);
                inbox.model.unread = inbox.unread;
            } while (inbox.dirty && !stopped);
            inbox.scanning = false;
        }

        private void stage (Folder model, GenericArray<string> uids, bool hidden) {
            var inbox = inboxes.lookup (model.id);
            if (inbox == null || stopped) { return; }
            foreach (var uid in uids.data) {
                if (hidden) { inbox.hidden.insert (uid, true); }
                else { inbox.hidden.remove (uid); }
            }
            scan.begin (inbox);
        }

        /* ----- System Notifications ----- */
        private void notify_message (Folder model, InboxItem item) {
            string sender = item.sender;
            var address = new Camel.InternetAddress ();
            if (address.decode (sender) > 0) {
                unowned string? name, email;
                if (address.get (0, out name, out email)) { sender = name ?? email ?? sender; }
            }
            var notification = new Notification (sender);
            notification.set_body (item.subject + "\n" + model.account);
            notification.set_icon (new ThemedIcon (Application.ID));
            notification.set_category ("email.arrived");
            notification.set_default_action_and_target ("app.open-mail", "(ss)", model.id, item.uid);
            app.send_notification (notifications.track (model.id, item.uid), notification);
        }

        /* ----- Dock Badges ----- */
        private void update_badge (bool clear = false) {
            int64 count = 0;
            if (!clear) {
                foreach (var inbox in inboxes.get_values ()) { count += inbox.unread; }
            }
            var properties = new VariantBuilder (new VariantType ("a{sv}"));
            properties.add ("{sv}", "count", new Variant.int64 (count));
            properties.add ("{sv}", "count-visible", new Variant.boolean (count > 0));
            try {
                app.get_dbus_connection ().emit_signal (null, app.get_dbus_object_path (), "com.canonical.Unity.LauncherEntry", "Update",
                    new Variant ("(sa{sv})", "application://" + Application.ID + ".desktop", properties));
            } catch (Error error) { debug ("Unable to update dock badge: %s", error.message); }
        }

        public void stop () {
            if (stopped) { return; }
            stopped = true;
            if (poll != 0) { Source.remove (poll); poll = 0; }
            if (dock_watch != 0) { Bus.unwatch_name (dock_watch); dock_watch = 0; }
            foreach (var inbox in inboxes.get_values ()) { inbox.folder.disconnect (inbox.handler); }
            notifications.save ();
            update_badge (true);
        }
    }
}
