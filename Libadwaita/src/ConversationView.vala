/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class ConversationView : Gtk.Box {
        private HashTable<Conversation, Gtk.Widget> pages = new HashTable<Conversation, Gtk.Widget> (direct_hash, direct_equal);
        private GenericArray<Conversation> recent = new GenericArray<Conversation> ();
        private Conversation? active;
        private ulong images_handler;
        private bool disposed;
        private Gtk.Stack stack;
        private EmptyState empty;
        private Settings settings;
        public signal void body_requested (Message message);
        public signal void star_requested (Message message, bool starred);
        public signal void compose_requested (ComposeMode mode, Message message);
        public signal void address_copied ();

        public ConversationView (Settings settings) {
            Object (orientation: Gtk.Orientation.VERTICAL);
            this.settings = settings;
            stack = new Gtk.Stack () { vexpand = true, hexpand = true };
            append (stack);
            empty = new EmptyState () {
                icon_name = "mail-read-symbolic", title = "Select Conversation"
            };
            empty.add_css_class ("reader-watermark");
            stack.add_named (empty, "empty");
            images_handler = settings.changed["always-load-remote-images"].connect (() => {
                var current = active;
                clear_pages ();
                show_conversation (current);
            });
        }

        public void show_selection (uint count) {
            empty.title = count > 1 ? "%u Conversations Selected".printf (count) : "Select Conversation";
            empty.description = "";
        }

        public void show_conversation (Conversation? conversation) {
            active = conversation;
            if (conversation == null) { stack.visible_child_name = "empty"; return; }
            var page = pages.lookup (conversation);
            if (page != null) {
                recent.remove (conversation);
                recent.add (conversation);
                stack.visible_child = page;
                prune ();
                for (uint i = 0; i < conversation.messages.get_n_items (); i++) {
                    var message = (Message) conversation.messages.get_item (i);
                    if (message.expanded && !message.loaded) { body_requested (message); }
                }
                return;
            }
            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 28, margin_bottom = 32, margin_start = 24, margin_end = 24
            };
            var title = new Gtk.Label (conversation.subject) { xalign = 0, wrap = true, selectable = true };
            title.add_css_class ("title-1");
            content_box.append (title);
            uint count = conversation.messages.get_n_items ();
            var info = new Gtk.Label ("%u %s".printf (count, count == 1 ? "message" : "messages")) { xalign = 0 };
            info.add_css_class ("dim-label");
            content_box.append (info);
            var cards = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { margin_top = 6 };
            for (uint i = 0; i < count; i++) {
                cards.append (message_card ((Message) conversation.messages.get_item (i), conversation.subject, i == count - 1));
            }
            content_box.append (cards);
            var clamp = new Adw.Clamp () { maximum_size = 860, tightening_threshold = 600, child = content_box };
            page = new Gtk.ScrolledWindow () { child = clamp, hscrollbar_policy = Gtk.PolicyType.NEVER };
            stack.add_child (page);
            pages.insert (conversation, page);
            recent.add (conversation);
            stack.visible_child = page;
            prune ();
        }

        /* ----- Rendered Conversation Cache ----- */
        private uint64 cost (Conversation conversation) {
            uint64 bytes = 0;
            for (uint i = 0; i < conversation.messages.get_n_items (); i++) {
                bytes += 256 * 1024 + ((Message) conversation.messages.get_item (i)).body.length * 4;
            }
            return bytes;
        }

        private void prune () {
            uint64 bytes = 0;
            foreach (var conversation in recent.data) { bytes += cost (conversation); }
            while (recent.length > 1 && (recent.length > 64 || bytes > 64 * 1024 * 1024)) {
                var oldest = recent[0];
                bytes -= cost (oldest);
                stack.remove (pages.lookup (oldest));
                pages.remove (oldest);
                recent.remove_index (0);
            }
        }

        private void clear_pages () {
            stack.visible_child_name = "empty";
            foreach (var conversation in recent.data) { stack.remove (pages.lookup (conversation)); }
            pages.remove_all ();
            recent = new GenericArray<Conversation> ();
        }

        protected override void dispose () {
            if (!disposed) {
                disposed = true;
                if (images_handler != 0) { settings.disconnect (images_handler); images_handler = 0; }
                clear_pages ();
            }
            base.dispose ();
        }

        private Gtk.Widget message_card (Message message, string subject, bool expanded) {
            var card = new MessageCard (message, subject, expanded);
            card.body_requested.connect ((message) => { body_requested (message); });
            card.star_requested.connect ((message, starred) => { star_requested (message, starred); });
            card.compose_requested.connect ((mode) => { compose_requested (mode, message); });
            card.address_copied.connect (() => address_copied ());
            return card;
        }
    }
}
