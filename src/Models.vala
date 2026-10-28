/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public enum FolderRole {
        REGULAR,
        STARRED,
        ARCHIVE,
        TRASH,
        INBOX,
        DRAFTS,
        SENT,
        JUNK
    }

    public class Folder : Object {
        public string name { get; set; }
        public string id { get; set; }
        public weak Folder? parent { get; set; }
        public string icon_name { get; set; }
        public string account { get; construct; }
        public bool is_account { get; construct; }
        public FolderRole role { get; set; }
        public uint unread { get; set; }
        public bool live { get; set; }
        public bool writable { get; set; default = true; }
        public bool system_folder { get; set; }
        public bool can_create { get; set; default = true; }
        public string remote_name { get; set; default = ""; }
        public bool selectable { get; set; default = true; }
        public bool loading { get; set; }
        public string? error_message { get; set; }
        public ListStore children { get; private set; }
        public ListStore conversations { get; private set; }

        public Folder (string name, string icon_name, string account, bool is_account = false, FolderRole role = FolderRole.REGULAR, string? id = null) {
            Object (name: name, icon_name: icon_name, account: account, is_account: is_account, role: role, id: id ?? Uuid.string_random ());
            children = new ListStore (typeof (Folder));
            conversations = new ListStore (typeof (Conversation));
        }

        public void add_child (Folder child) {
            child.parent = this;
            children.append (child);
        }

        public bool is_in_trash () {
            for (Folder? folder = this; folder != null; folder = folder.parent) {
                if (folder.role == FolderRole.TRASH) {
                    return true;
                }
            }
            return false;
        }

        public void add_conversation (Conversation conversation) {
            conversations.append (conversation);
            if (conversation.unread) {
                unread++;
            }
        }
    }

    public class Conversation : Object {
        public bool live { get; set; }
        public int64 timestamp { get; construct; }
        public string sender { get; construct; }
        public string subject { get; construct; }
        public string preview { get; construct; }
        public string time_label { get; construct; }
        public bool unread { get; set; }
        public bool starred { get; set; }
        public ListStore messages { get; private set; }

        public Conversation (string sender, string subject, string preview, string time_label,
                             bool unread = false, bool starred = false, int64 timestamp = 0) {
            Object (sender: sender, subject: subject, preview: preview, time_label: time_label,
                    unread: unread, starred: starred, timestamp: timestamp);
            messages = new ListStore (typeof (Message));
        }

        public bool matches (string query) {
            if (query == "") {
                return true;
            }
            return (sender + " " + subject + " " + preview).casefold ().contains (query.casefold ());
        }
    }

    public class Message : Object {
        public string uid { get; set; default = ""; }
        public string? message_id { get; set; }
        public string? reply_to { get; set; }
        public string? cc { get; set; }
        public string? bcc { get; set; }
        public string? in_reply_to { get; set; }
        public Camel.MimeMessage? draft_mime { get; set; }
        public bool read_only { get; set; }
        public bool loaded { get; set; }
        public bool expanded { get; set; }
        public bool is_html { get; set; }
        public bool starred { get; set; }
        public string sender { get; construct; }
        public string address { get; construct; }
        public string recipient { get; construct; }
        public string time_label { get; construct; }
        public string body { get; set; }

        public Message (string sender, string address, string recipient, string time_label, string body) {
            Object (sender: sender, address: address, recipient: recipient, time_label: time_label, body: body);
        }
    }
}
