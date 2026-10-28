/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public delegate void UndoAction ();

    public class UndoOperation : Object {
        private UndoAction? action;
        public UndoOperation (owned UndoAction action) { this.action = (owned) action; }
        public void undo () {
            if (action != null) {
                action ();
                action = null;
            }
        }
    }

    public class ConversationDrag : Object {
        public Folder source;
        public Conversation[] conversations;
        public ConversationDrag (Folder source, Conversation[] conversations) {
            this.source = source;
            this.conversations = conversations;
        }
    }

    public class MailOperations : Object {
        private MailData data;
        private MailBackend backend;
        private bool busy;
        public signal void started (string title, UndoOperation? undo);
        public signal void completed (string title, UndoOperation? undo);

        public MailOperations (MailData data, MailBackend backend) { this.data = data; this.backend = backend; }

        public static string? validate_name (Folder parent, string name, Folder? existing = null) {
            if (name == "" || name == "." || name == ".." || name.contains ("/") || name.contains ("\\")) {
                return "Choose a name without path separators.";
            }
            for (uint i = 0; i < parent.children.get_n_items (); i++) {
                var child = (Folder) parent.children.get_item (i);
                if (child != existing && child.name.casefold () == name.casefold ()) {
                    return "A folder with this name already exists.";
                }
            }
            return null;
        }

        public bool reorder (Folder source, Folder destination, bool after) {
            if (source == destination || source.is_account || destination.is_account || source.parent == null ||
                source.parent != destination.parent || !data.contains_folder (source) || !data.contains_folder (destination)) {
                return false;
            }
            var parent = source.parent;
            uint old_position = 0, target = 0;
            if (!parent.children.find (source, out old_position) || !parent.children.find (destination, out target)) {
                return false;
            }
            uint insertion = target + (after ? 1u : 0u);
            if (old_position < insertion) { insertion--; }
            if (old_position == insertion) { return true; }
            data.folders_changing ();
            parent.children.remove (old_position);
            parent.children.insert (insertion, source);
            data.remember_order (parent);
            data.folders_changed (null);
            return true;
        }

        public bool can_move (ConversationDrag drag, Folder destination) {
            if (busy || !drag.source.writable || !destination.writable || !destination.selectable) { return false; }
            if (destination.is_account || destination.role == FolderRole.STARRED || drag.source.role == FolderRole.STARRED ||
                drag.source == destination || data.account_for (drag.source) != data.account_for (destination) || drag.conversations.length == 0 ||
                !data.contains_folder (drag.source) || !data.contains_folder (destination)) {
                return false;
            }
            foreach (var conversation in drag.conversations) {
                uint position = 0;
                if (!drag.source.conversations.find (conversation, out position) || destination.conversations.find (conversation, out position)) {
                    return false;
                }
            }
            return true;
        }

        public bool move (ConversationDrag drag, Folder destination) {
            if (!can_move (drag, destination)) { return false; }
            backend.begin_background ();
            backend.stage_messages (drag, true);
            uint[] positions = {};
            uint unread = drag.source.unread;
            foreach (var conversation in drag.conversations) {
                uint position;
                drag.source.conversations.find (conversation, out position);
                positions += position;
            }
            foreach (var conversation in drag.conversations) {
                uint position;
                if (drag.source.conversations.find (conversation, out position)) { drag.source.conversations.remove (position); }
                if (conversation.unread && drag.source.unread > 0) { drag.source.unread--; }
            }
            started ("Moving messages…", null);
            backend.move.begin (drag, destination, (obj, result) => {
                try {
                    var undo = backend.move.end (result);
                    completed ("Moved to %s".printf (destination.name), undo);
                } catch (Error error) {
                    for (int i = 0; i < drag.conversations.length; i++) {
                        uint position;
                        if (!drag.source.conversations.find (drag.conversations[i], out position)) {
                            drag.source.conversations.insert (uint.min (positions[i], drag.source.conversations.get_n_items ()), drag.conversations[i]);
                        }
                    }
                    drag.source.unread = unread;
                    completed ("Messages could not be moved", null);
                    report_error (error);
                } finally {
                    backend.stage_messages (drag, false);
                    backend.end_background ();
                }
            });
            return true;
        }

        public bool trash_folder (Folder folder) {
            if (busy || folder.is_account || folder.system_folder || folder.role != FolderRole.REGULAR || !folder.writable || folder.is_in_trash ()) { return false; }
            var trash = data.find_folder (data.account_for (folder), FolderRole.TRASH);
            if (trash == null) { return false; }
            busy = true;
            backend.rename_folder.begin (folder, folder.name, trash, (obj, result) => {
                busy = false;
                try {
                    backend.rename_folder.end (result);
                    data.folders_changing ();
                    uint position;
                    if (folder.parent.children.find (folder, out position)) { folder.parent.children.remove (position); }
                    folder.name = folder.remote_name.substring (folder.remote_name.last_index_of ("/") + 1);
                    trash.add_child (folder);
                    data.folders_changed (trash);
                    completed ("Folder moved to Trash", null);
                } catch (Error error) { report_error (error); }
            });
            return true;
        }

        public void save_folder (Folder parent, string name, Folder? existing = null) {
            save_folder_async.begin (parent, name, existing, (obj, result) => {
                try { save_folder_async.end (result); } catch (Error error) { report_error (error); }
            });
        }

        private async void save_folder_async (Folder parent, string name, Folder? existing) throws Error {
            if (busy) { throw new IOError.BUSY ("Another mail operation is still running."); }
            var validation = validate_name (parent, name, existing);
            if (validation != null) { throw new IOError.INVALID_ARGUMENT (validation); }
            busy = true;
            try {
                var folder = existing;
                if (folder == null) { folder = yield backend.create_folder (parent, name); }
                else { yield backend.rename_folder (folder, name); }
                data.folders_changing ();
                if (existing == null) { parent.add_child (folder); }
                folder.name = name;
                data.remember_order (parent);
                data.folders_changed (folder);
            } finally { busy = false; }
        }

        private void report_error (Error error) {
            var dialog = new Adw.AlertDialog ("Mail Operation Failed", error.message);
            dialog.add_response ("close", "Close");
            dialog.present (((Gtk.Application) GLib.Application.get_default ()).active_window);
        }

        public bool can_empty_trash (Folder trash) {
            return !busy && trash.writable && trash.selectable && trash.role == FolderRole.TRASH && data.contains_folder (trash);
        }

        public void request_empty_trash (Folder trash, Gtk.Widget parent) {
            if (!can_empty_trash (trash)) { return; }
            var dialog = new Adw.AlertDialog ("Empty Trash?", "All messages and subfolders in Trash will be permanently removed.");
            dialog.add_responses ("cancel", "Cancel", "empty", "Empty Trash", null);
            dialog.close_response = "cancel";
            dialog.default_response = "cancel";
            dialog.set_response_appearance ("empty", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((id) => { if (id == "empty") { empty_trash (trash); } });
            dialog.present (parent);
        }

        public void empty_trash (Folder trash) {
            if (!can_empty_trash (trash)) { return; }
            busy = true;
            backend.begin_background ();
            var saved = new GenericArray<Conversation> ();
            for (uint i = 0; i < trash.conversations.get_n_items (); i++) { saved.add ((Conversation) trash.conversations.get_item (i)); }
            var payload = new ConversationDrag (trash, saved.data);
            backend.stage_messages (payload, true);
            trash.conversations.remove_all ();
            started ("Emptying Trash…", null);
            backend.empty_trash.begin (trash, (obj, result) => {
                busy = false;
                try {
                    backend.empty_trash.end (result);
                    data.folders_changed (trash);
                    completed ("Trash emptied", null);
                } catch (Error error) {
                    foreach (var conversation in saved.data) {
                        uint position;
                        if (!trash.conversations.find (conversation, out position)) { trash.conversations.append (conversation); }
                    }
                    completed ("Trash could not be emptied", null);
                    report_error (error);
                } finally {
                    backend.stage_messages (payload, false);
                    backend.end_background ();
                }
            });
        }
    }
}
