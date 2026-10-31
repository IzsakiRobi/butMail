/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class MainWindow : Adw.ApplicationWindow {
        private Settings settings;
        private MailData data;
        private MailOperations operations;
        private Adw.OverlaySplitView folders_split;
        private Adw.NavigationSplitView messages_split;
        private Gtk.Label folder_title;
        private Gtk.Label folder_subtitle;
        private Adw.WindowTitle message_title;
        private FolderSidebar folders;
        private ConversationList conversations;
        private ConversationView messages;
        private Folder? current_folder;
        private Conversation? current_conversation;
        private SimpleAction reply_action;
        private SimpleAction reply_all_action;
        private SimpleAction forward_action;
        private SimpleAction mark_action;
        private SimpleAction read_action;
        private SimpleAction unread_action;
        private HashTable<Conversation, ulong?> selection_handlers = new HashTable<Conversation, ulong?> (direct_hash, direct_equal);
        private Gtk.MenuButton move_button;
        private SimpleAction archive_action;
        private SimpleAction trash_action;
        private SimpleAction empty_trash_action;
        private Adw.ToastOverlay toast_overlay;
        private Adw.Toast? move_toast;
        private MailBackend backend;
        private InboxMonitor inbox_monitor;
        private bool latest_pending = true;
        private Folder? latest_inbox;
        private string? notification_folder;
        private string? notification_uid;
        private uint read_timeout;
        private bool automatic_read_suppressed;
        private Adw.Spinner refresh_spinner;
        private Gtk.Box connection_dot;
        private SimpleAction refresh_action;
        private bool connecting = true;
        private ulong loading_handler;
        private Cancellable folder_loading = new Cancellable ();
        private Cancellable message_loading = new Cancellable ();

        public MainWindow (Adw.Application application) {
            Object (application: application, title: "butMail", width_request: 360, height_request: 360);
            add_css_class ("butmail");
            settings = ((Application) application).settings;
            default_width = settings.get_int ("window-width");
            default_height = settings.get_int ("window-height");
            maximized = settings.get_boolean ("window-maximized");
            close_request.connect (() => {
                save_geometry ();
                if (settings.get_boolean ("run-in-background") && !((Application) application).quitting) {
                    cancel_read_timer ();
                    message_loading.cancel ();
                    visible = false;
                    return true;
                }
                inbox_monitor.stop ();
                clear_selection_handlers ();
                if (current_folder != null && loading_handler != 0) { current_folder.disconnect (loading_handler); loading_handler = 0; }
                cancel_read_timer ();
                bool other_window = false;
                foreach (var window in application.get_windows ()) { other_window |= window != this; }
                if (!other_window) { backend.cancel (); }
                folder_loading.cancel ();
                cancel_read_timer ();
                message_loading.cancel ();
                return false;
            });

            data = new MailData (settings);
            backend = new MailBackend ();
            inbox_monitor = new InboxMonitor ((Application) application, backend);
            inbox_monitor.mail_arrived.connect ((folder) => {
                if (!is_active) { latest_pending = true; latest_inbox = folder; }
            });
            backend.folder_updated.connect (() => {
                open_pending_notification ();
                reveal_latest ();
            });
            operations = new MailOperations (data, backend);
            operations.completed.connect (show_operation);
            operations.started.connect (show_progress);
            folders = new FolderSidebar (data, operations);
            conversations = new ConversationList (settings);
            messages = new ConversationView (settings);
            messages.body_requested.connect ((message) => {
                if (current_conversation == null) { return; }
                backend.load_conversation.begin (current_conversation, message_loading, message, (obj, result) => {
                    try { backend.load_conversation.end (result); }
                    catch (Error error) { if (!(error is IOError.CANCELLED)) { message.load_error = "Unable to load message: " + error.message; } }
                });
            });
            messages.star_requested.connect ((message, starred) => {
                if (current_folder == null || current_conversation == null) { return; }
                backend.mark.begin (current_folder, new Conversation[] { current_conversation }, starred ? "star" : "unstar", message, (obj, result) => {
                    try { backend.mark.end (result); }
                    catch (Error error) { show_operation ("Unable to star message: " + error.message, null); }
                });
            });
            messages.compose_requested.connect ((mode, message) => { open_composer (mode, message); });
            messages.address_copied.connect (() => {
                toast_overlay.add_toast (new Adw.Toast ("Address copied") { timeout = 2, priority = Adw.ToastPriority.HIGH });
            });
            var compose_action = new SimpleAction ("compose", null);
            compose_action.set_enabled (false);
            compose_action.activate.connect (() => open_composer (ComposeMode.NEW));
            add_action (compose_action);
            var new_folder = new SimpleAction ("new-folder", null);
            new_folder.set_enabled (false);
            new_folder.activate.connect (create_folder);
            add_action (new_folder);
            reply_action = new SimpleAction ("reply", null);
            reply_action.activate.connect (() => open_composer (ComposeMode.REPLY));
            reply_action.set_enabled (false);
            add_action (reply_action);
            reply_all_action = new SimpleAction ("reply-all", null);
            reply_all_action.activate.connect (() => open_composer (ComposeMode.REPLY_ALL));
            reply_all_action.set_enabled (false);
            add_action (reply_all_action);
            forward_action = new SimpleAction ("forward", null);
            forward_action.activate.connect (() => open_composer (ComposeMode.FORWARD));
            forward_action.set_enabled (false);
            add_action (forward_action);
            mark_action = new SimpleAction ("mark", VariantType.STRING);
            mark_action.activate.connect ((value) => mark_current (value.get_string ()));
            mark_action.set_enabled (false);
            add_action (mark_action);
            read_action = new SimpleAction ("mark-read", null);
            read_action.activate.connect (() => mark_current ("read"));
            read_action.set_enabled (false);
            add_action (read_action);
            unread_action = new SimpleAction ("mark-unread", null);
            unread_action.activate.connect (() => mark_current ("unread"));
            unread_action.set_enabled (false);
            add_action (unread_action);
            archive_action = new SimpleAction ("archive", null);
            archive_action.activate.connect (() => move_to_role (FolderRole.ARCHIVE));
            archive_action.set_enabled (false);
            add_action (archive_action);
            trash_action = new SimpleAction ("trash", null);
            trash_action.activate.connect (() => move_to_role (FolderRole.TRASH));
            trash_action.set_enabled (false);
            add_action (trash_action);
            empty_trash_action = new SimpleAction ("empty-trash", null);
            empty_trash_action.set_enabled (false);
            empty_trash_action.activate.connect (() => operations.request_empty_trash (current_folder, this));
            add_action (empty_trash_action);
            folder_title = new Gtk.Label ("Mail") { ellipsize = Pango.EllipsizeMode.END };
            folder_title.add_css_class ("heading");
            folder_subtitle = new Gtk.Label ("Connecting…") { ellipsize = Pango.EllipsizeMode.END };
            folder_subtitle.add_css_class ("dim-label");
            folder_subtitle.add_css_class ("caption");
            message_title = new Adw.WindowTitle ("Conversation", "Preview");

            var folders_toolbar = new Adw.ToolbarView () { content = folders };
            var folders_header = new Adw.HeaderBar () {
                title_widget = new Adw.WindowTitle ("butMail", ""),
                show_end_title_buttons = false
            };
            refresh_action = new SimpleAction ("refresh", null);
            refresh_action.activate.connect (() => {
                if (!connecting && backend.pending_operations == 0 && current_folder != null &&
                    current_folder.selectable && !current_folder.loading) {
                    load_current_folder (true);
                }
            });
            add_action (refresh_action);
            var menu = new Menu ();
            var app_menu = new Menu ();
            app_menu.append ("Refresh Mail", "win.refresh");
            app_menu.append ("Preferences", "app.preferences");
            app_menu.append ("About butMail", "app.about");
            app_menu.append ("Quit", "app.quit");
            menu.append_section (null, app_menu);
            var hide_folders = new Gtk.Button.from_icon_name ("sidebar-show-symbolic") { tooltip_text = "Hide Folders" };
            hide_folders.clicked.connect (() => { folders_split.show_sidebar = false; });
            folders_header.pack_start (hide_folders);
            folders_header.pack_end (new Gtk.Button.from_icon_name ("mail-message-new-symbolic") {
                action_name = "win.compose", tooltip_text = "New Message (Ctrl+N)"
            });
            folders_toolbar.add_top_bar (folders_header);
            var folder_actions = new Gtk.ActionBar ();
            folder_actions.pack_start (new Gtk.Button.from_icon_name ("folder-new-symbolic") {
                action_name = "win.new-folder", tooltip_text = "New Folder"
            });
            folder_actions.pack_end (new Gtk.MenuButton () {
                icon_name = "emblem-system-symbolic", menu_model = menu, tooltip_text = "Application Menu"
            });
            folders_toolbar.add_bottom_bar (folder_actions);

            var list_toolbar = new Adw.ToolbarView () { content = conversations };
            connection_dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            connection_dot.add_css_class ("unread-dot");
            connection_dot.add_css_class ("connection-dot");
            var folder_heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { halign = Gtk.Align.CENTER };
            folder_heading.append (folder_title);
            folder_heading.append (connection_dot);
            var folder_caption = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
            folder_caption.append (folder_heading);
            folder_caption.append (folder_subtitle);
            var list_header = new Adw.HeaderBar () { title_widget = folder_caption };
            var show_folders = new Gtk.Button.from_icon_name ("sidebar-show-symbolic") {
                tooltip_text = "Show Folders", visible = false
            };
            show_folders.clicked.connect (() => { folders_split.show_sidebar = true; });
            list_header.pack_start (show_folders);
            var compose_fallback = new Gtk.Button.from_icon_name ("mail-message-new-symbolic") {
                action_name = "win.compose", tooltip_text = "New Message (Ctrl+N)", visible = false
            };
            list_header.pack_end (compose_fallback);
            list_toolbar.add_top_bar (list_header);
            var list_actions = new Gtk.ActionBar ();
            list_actions.add_css_class ("conversation-footer");
            list_actions.add_css_class ("empty-list");
            conversations.notify["has-messages"].connect (() => {
                if (conversations.has_messages) { list_actions.remove_css_class ("empty-list"); }
                else { list_actions.add_css_class ("empty-list"); }
            });
            var refresh_button = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                action_name = "win.refresh", tooltip_text = "Refresh Mail (F5)"
            };
            backend.notify["online"].connect (update_connection_indicator);
            backend.notify["is-connecting"].connect (update_connection_indicator);
            update_connection_indicator ();
            var fallback_menu = new Gtk.MenuButton () {
                icon_name = "emblem-system-symbolic", menu_model = menu, tooltip_text = "Application Menu", visible = false
            };
            list_actions.pack_start (fallback_menu);
            list_actions.pack_start (refresh_button);
            refresh_spinner = new Adw.Spinner () {
                width_request = 16, height_request = 16, valign = Gtk.Align.CENTER, tooltip_text = "Refreshing…"
            };
            list_actions.pack_end (refresh_spinner);
            backend.notify["pending-operations"].connect (update_refresh_state);
            update_refresh_state ();
            list_toolbar.add_bottom_bar (list_actions);

            var message_toolbar = new Adw.ToolbarView () { content = messages };
            var message_header = new Adw.HeaderBar () { title_widget = message_title };
            message_header.pack_start (new Gtk.Button () {
                child = new Gtk.Image.from_icon_name ("butmail-reply-symbolic") { pixel_size = 18 },
                action_name = "win.reply", tooltip_text = "Reply (Ctrl+R)"
            });
            message_header.pack_start (new Gtk.Button () {
                child = new Gtk.Image.from_icon_name ("butmail-reply-all-symbolic") { pixel_size = 18 },
                action_name = "win.reply-all", tooltip_text = "Reply All (Ctrl+Shift+R)"
            });
            message_header.pack_start (new Gtk.Button () {
                child = new Gtk.Image.from_icon_name ("butmail-forward-symbolic") { pixel_size = 18 },
                action_name = "win.forward", tooltip_text = "Forward (Ctrl+Shift+F)"
            });
            var marks = new Menu ();
            marks.append ("Star", "win.mark::star");
            marks.append ("Unstar", "win.mark::unstar");
            marks.append ("Mark as Read", "win.mark-read");
            marks.append ("Mark as Unread", "win.mark-unread");
            var mark_button = new Gtk.MenuButton () {
                icon_name = "starred-symbolic", tooltip_text = "Mark Conversation", menu_model = marks
            };
            mark_action.bind_property ("enabled", mark_button, "sensitive", BindingFlags.SYNC_CREATE);
            var toolbar_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            toolbar_actions.append (mark_button);
            var folder_popup = new FolderPickerPopover ();
            folder_popup.popover.map.connect (() => {
                folder_popup.set_source (data.account_for (current_folder), current_folder);
            });
            folder_popup.folder_selected.connect (move_current);
            move_button = new Gtk.MenuButton () {
                icon_name = "folder-symbolic", tooltip_text = "Move to Folder",
                popover = folder_popup.popover, direction = Gtk.ArrowType.DOWN, sensitive = false
            };
            toolbar_actions.append (move_button);
            toolbar_actions.append (new Gtk.Button.from_icon_name ("package-x-generic-symbolic") {
                action_name = "win.archive", tooltip_text = "Archive"
            });
            toolbar_actions.append (new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                action_name = "win.trash", tooltip_text = "Move to Trash"
            });
            message_header.pack_end (toolbar_actions);
            message_toolbar.add_top_bar (message_header);
            var message_page = new Adw.NavigationPage (message_toolbar, "Conversation");
            messages_split = new Adw.NavigationSplitView () {
                content = message_page, min_sidebar_width = 280, max_sidebar_width = 600,
                sidebar_width_fraction = settings.get_double ("conversation-width-fraction")
            };
            var list_page = new Adw.NavigationPage (SplitResizeHandle.wrap (list_toolbar, messages_split, 280, 600), "Conversations");
            messages_split.sidebar = list_page;
            folders_split = new Adw.OverlaySplitView () {
                content = messages_split, min_sidebar_width = 220, max_sidebar_width = 500,
                sidebar_width_fraction = settings.get_double ("folder-width-fraction")
            };
            folders_split.sidebar = SplitResizeHandle.wrap (folders_toolbar, folders_split, 220, 500);
            folders_split.notify["show-sidebar"].connect (() => {
                show_folders.visible = !folders_split.show_sidebar;
                compose_fallback.visible = !folders_split.show_sidebar;
                fallback_menu.visible = !folders_split.show_sidebar;
            });
            toast_overlay = new Adw.ToastOverlay () { child = folders_split };
            content = toast_overlay;

            var folders_breakpoint = new Adw.Breakpoint (Adw.BreakpointCondition.parse ("max-width: 1100sp"));
            folders_breakpoint.add_setter (folders_split, "collapsed", true);
            folders_breakpoint.add_setter (folders_split, "show-sidebar", false);
            add_breakpoint (folders_breakpoint);
            var messages_breakpoint = new Adw.Breakpoint (Adw.BreakpointCondition.parse ("max-width: 760sp"));
            messages_breakpoint.add_setter (messages_split, "collapsed", true);
            add_breakpoint (messages_breakpoint);

            folders.folder_selected.connect ((folder) => {
                folder_loading.cancel ();
                cancel_read_timer ();
                message_loading.cancel ();
                folder_loading = new Cancellable ();
                if (current_folder != null && loading_handler != 0) { current_folder.disconnect (loading_handler); }
                current_folder = folder;
                loading_handler = folder.notify["loading"].connect (update_refresh_state);
                update_refresh_state ();
                empty_trash_action.set_enabled (operations.can_empty_trash (folder));
                folder_title.label = folder.name;
                folder_subtitle.label = folder.account;
                list_page.title = folder.name;
                conversations.show_folder (folder);
                load_current_folder ();
                messages_split.show_content = false;
                if (folders_split.collapsed) {
                    folders_split.show_sidebar = false;
                }
            });
            conversations.conversation_selected.connect ((conversation) => {
                cancel_read_timer ();
                if (conversation != current_conversation) { automatic_read_suppressed = false; }
                message_loading.cancel ();
                message_loading = new Cancellable ();
                current_conversation = conversation;
                clear_selection_handlers ();
                foreach (var selected in conversations.get_selected_conversations ()) {
                    selection_handlers.insert (selected, selected.notify["unread"].connect (update_mail_actions));
                }
                empty_trash_action.set_enabled (current_folder != null && operations.can_empty_trash (current_folder));
                uint selected_count = (uint) conversations.get_selected_conversations ().length;
                bool can_compose = conversation != null && conversation.messages.get_n_items () > 0;
                reply_action.set_enabled (can_compose);
                reply_all_action.set_enabled (can_compose);
                forward_action.set_enabled (can_compose);
                update_mail_actions ();
                messages.show_selection (selected_count);
                messages.show_conversation (conversation);
                message_title.title = conversation == null ? "Conversation" : conversation.sender;
                message_title.subtitle = current_folder != null ? current_folder.account : "";
                if (conversation != null && conversation.live && visible) {
                    var loading = message_loading;
                    backend.load_conversation.begin (conversation, loading, null, (obj, result) => {
                        try {
                            backend.load_conversation.end (result);
                            if (conversation == current_conversation && conversation.unread && visible &&
                                !automatic_read_suppressed && !loading.is_cancelled ()) {
                                read_timeout = Timeout.add ((uint) settings.get_int ("mark-read-delay") * 1000, () => {
                                    read_timeout = 0;
                                    if (conversation == current_conversation && visible &&
                                        !automatic_read_suppressed && !loading.is_cancelled ()) { mark_current ("read"); }
                                    return Source.REMOVE;
                                });
                            }
                        }
                        catch (Error error) {
                            if (!(error is IOError.CANCELLED)) {
                                for (uint i = 0; i < conversation.messages.get_n_items (); i++) {
                                    var message = (Message) conversation.messages.get_item (i);
                                    if (!message.loaded) { message.load_error = "Unable to load message: " + error.message; }
                                }
                            }
                        }
                    });
                }
            });
            conversations.conversation_activated.connect (() => {
                if (current_folder != null && current_folder.role == FolderRole.DRAFTS && current_conversation != null) {
                    open_composer (ComposeMode.DRAFT);
                } else { messages_split.show_content = true; }
            });
            var clear = new SimpleAction ("clear-selection", null);
            clear.activate.connect (() => {
                conversations.clear_selection ();
                messages_split.show_content = false;
            });
            add_action (clear);
            conversations.show_status ("Loading Folders…", "");
            backend.failed.connect ((message) => { show_operation (message, null); });
            backend.folders_updated.connect ((account, children) => { data.update_account (account, children, current_folder); });
            data.folders_changed.connect (() => {
                update_mail_actions ();
                for (uint i = 0; i < data.accounts.get_n_items (); i++) { backend.cache_account ((Folder) data.accounts.get_item (i)); }
                open_pending_notification ();
            });
            backend.folders_loaded.connect ((accounts, preferred) => {
                compose_action.set_enabled (true);
                new_folder.set_enabled (true);
                data.replace_accounts (accounts, preferred);
                if (preferred == null) { conversations.show_status ("Loading Folders…", ""); }
            });
            backend.start.begin ((obj, result) => {
                try {
                    backend.start.end (result);
                }
                catch (Error error) {
                    if (!(error is IOError.CANCELLED)) {
                        conversations.show_status ("Unable to Connect", error.message);
                    }
                } finally {
                    connecting = false;
                    update_refresh_state ();
                    reveal_latest ();
                }
            });
            map.connect (() => { conversations.refresh_selection (); reveal_latest (); });
            notify["is-active"].connect (() => { if (is_active) { reveal_latest (); } });
        }

        private void save_geometry () {
            settings.set_double ("folder-width-fraction", folders_split.sidebar_width_fraction);
            settings.set_double ("conversation-width-fraction", messages_split.sidebar_width_fraction);
            settings.set_boolean ("window-maximized", maximized);
            if (!maximized && !fullscreened) {
                settings.set_int ("window-width", default_width);
                settings.set_int ("window-height", default_height);
            }
        }

        /* ----- Window and Notification Navigation ----- */
        private void reveal_latest () {
            if (!latest_pending || !is_active || notification_folder != null) { return; }
            if (latest_inbox != null) {
                var inbox = latest_inbox;
                latest_inbox = null;
                if (current_folder != inbox) { folders.select_folder (inbox); }
            }
            if (current_folder == null) { return; }
            if (conversations.has_messages) {
                latest_pending = false;
                conversations.scroll_to_top ();
            } else if (!connecting && !current_folder.loading) { latest_pending = false; }
        }

        public void open_mail (string folder_id, string uid) {
            latest_pending = false;
            latest_inbox = null;
            notification_folder = folder_id;
            notification_uid = uid;
            open_pending_notification ();
        }

        private Folder? find_notification_folder (Folder root) {
            if (root.id == notification_folder) { return root; }
            for (uint i = 0; i < root.children.get_n_items (); i++) {
                var found = find_notification_folder ((Folder) root.children.get_item (i));
                if (found != null) { return found; }
            }
            return null;
        }

        private void open_pending_notification () {
            if (notification_folder == null || notification_uid == null) { return; }
            for (uint i = 0; i < data.accounts.get_n_items (); i++) {
                var folder = find_notification_folder ((Folder) data.accounts.get_item (i));
                if (folder == null) { continue; }
                if (current_folder != folder) { folders.select_folder (folder); }
                if (conversations.select_message (notification_uid)) {
                    notification_folder = null;
                    notification_uid = null;
                    messages_split.show_content = true;
                }
                return;
            }
        }

        private void update_mail_actions () {
            var selected = conversations.get_selected_conversations ();
            uint selected_count = (uint) selected.length;
            bool writable = current_folder != null && current_folder.writable && selected_count > 0;
            bool has_read = false, has_unread = false;
            foreach (var conversation in selected) {
                has_unread |= conversation.unread;
                has_read |= !conversation.unread;
            }
            mark_action.set_enabled (writable);
            read_action.set_enabled (writable && has_unread);
            unread_action.set_enabled (writable && has_read);
            bool can_move = current_folder != null && current_folder.writable && selected_count > 0 && current_folder.role != FolderRole.STARRED;
            move_button.sensitive = can_move;
            var account = current_folder != null ? data.account_for (current_folder) : null;
            archive_action.set_enabled (can_move && current_folder.role != FolderRole.ARCHIVE &&
                data.find_folder (account, FolderRole.ARCHIVE) != null);
            trash_action.set_enabled (can_move && current_folder.role != FolderRole.TRASH &&
                data.find_folder (account, FolderRole.TRASH) != null);
        }

        private void clear_selection_handlers () {
            selection_handlers.foreach ((conversation, handler) => conversation.disconnect (handler));
            selection_handlers.remove_all ();
        }

        private void update_connection_indicator () {
            connection_dot.remove_css_class ("connected");
            connection_dot.remove_css_class ("connecting");
            connection_dot.remove_css_class ("disconnected");
            string state = backend.is_connecting ? "Connecting…" : backend.online ? "Connected" : "Disconnected";
            connection_dot.add_css_class (backend.is_connecting ? "connecting" : backend.online ? "connected" : "disconnected");
            connection_dot.tooltip_text = state;
        }

        private void update_refresh_state () {
            bool busy = connecting || backend.pending_operations > 0 || (current_folder != null && current_folder.loading);
            refresh_spinner.visible = busy;
        }

        private void load_current_folder (bool refresh = false) {
            if (current_folder == null) { return; }
            folder_loading.cancel ();
            folder_loading = new Cancellable ();
            var folder = current_folder;
            backend.load_folder.begin (folder, folder_loading, refresh, (obj, result) => {
                try { backend.load_folder.end (result); }
                catch (Error error) {
                    if (!(error is IOError.CANCELLED)) { show_operation ("Unable to load messages: " + error.message, null); }
                } finally { reveal_latest (); }
            });
        }

        private void create_folder () {
            if (current_folder == null) { return; }
            var dialog = new NewFolderDialog (data.accounts, data.account_for (current_folder));
            dialog.folder_created.connect ((account, name) => {
                operations.save_folder (account, name);
            });
            dialog.present (this);
        }

        private void cancel_read_timer () {
            if (read_timeout != 0) { Source.remove (read_timeout); read_timeout = 0; }
        }

        private void mark_current (string flag) {
            cancel_read_timer ();
            if (current_folder == null) { return; }
            if (flag == "unread" && current_conversation != null) { automatic_read_suppressed = true; }
            backend.mark.begin (current_folder, conversations.get_selected_conversations (), flag, null, (obj, result) => {
                try { backend.mark.end (result); }
                catch (Error error) { show_operation ("Unable to mark messages: " + error.message, null); }
            });
        }

        private void move_to_role (FolderRole role) {
            if (current_folder == null) { return; }
            var destination = data.find_folder (data.account_for (current_folder), role);
            if (destination != null) {
                move_current (destination);
            }
        }

        private void move_current (Folder destination) {
            if (current_folder == null) { return; }
            operations.move (new ConversationDrag (current_folder, conversations.get_selected_conversations ()), destination);
        }

        private void show_progress (string title, UndoOperation? undo) {
            create_progress (title, undo);
        }

        private Adw.Toast create_progress (string title, UndoOperation? undo) {
            if (move_toast != null) { move_toast.dismiss (); }
            var toast = new Adw.Toast (title) { timeout = 0, use_markup = false };
            if (undo != null) {
                toast.button_label = "Undo";
                toast.button_clicked.connect (() => undo.undo ());
            }
            move_toast = toast;
            toast_overlay.add_toast (toast);
            return toast;
        }

        private void show_operation (string title, UndoOperation? undo) {
            if (move_toast != null) { move_toast.dismiss (); }
            uint seconds = (uint) settings.get_int ("undo-time");
            var toast = new Adw.Toast (title) { timeout = seconds > 0 ? seconds : 3, use_markup = false };
            if (undo != null && seconds > 0) {
                toast.button_label = "Undo";
                toast.button_clicked.connect (() => undo.undo ());
            }
            move_toast = toast;
            toast_overlay.add_toast (toast);
        }

        private void open_composer (ComposeMode mode, Message? source_message = null) {
            open_composer_async.begin (mode, source_message);
        }

        private async void open_composer_async (ComposeMode mode, Message? source_message) {
            if (current_folder == null) { return; }
            var folder = current_folder;
            var conversation = mode == ComposeMode.NEW ? null : current_conversation;
            if (conversation != null) {
                try { yield backend.load_conversation (conversation, new Cancellable (), source_message); }
                catch (Error error) { show_operation ("Unable to open message: " + error.message, null); return; }
            }
            var composer = new ComposerWindow (application, this, data.accounts, backend, folder.account, mode, conversation, source_message, data.account_for (folder));
            composer.queued.connect (create_progress);
            composer.completed.connect ((title) => { show_operation (title, null); });
            composer.present ();
        }
    }
}
