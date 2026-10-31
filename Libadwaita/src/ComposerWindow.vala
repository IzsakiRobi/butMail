/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public enum ComposeMode {
        NEW,
        REPLY,
        REPLY_ALL,
        FORWARD,
        DRAFT
    }

    public class ComposerWindow : Adw.ApplicationWindow {
        public signal Adw.Toast? queued (string title, UndoOperation? undo);
        public signal void completed (string title);
        private MailBackend backend;
        private ListStore accounts;
        private bool sending;
        private string? reply_id;
        private string? draft_uid;
        private Folder? draft_account;
        private GenericArray<Camel.MimePart> preserved_parts = new GenericArray<Camel.MimePart> ();
        private bool attachments_changed;
        private Gtk.Button send_button;
        private Gtk.DropDown sender;
        private Gtk.Entry recipient;
        private Gtk.Entry cc;
        private Gtk.Entry bcc;
        private Gtk.Entry subject;
        private RichTextEditor editor;
        private string[] initial_fields;
        private uint initial_sender;
        private bool discard_confirmed;
        private Adw.AlertDialog? close_dialog;
        private Gtk.FlowBox attachment_box;
        private GenericArray<File> attachments = new GenericArray<File> ();
        private Cancellable cancellable = new Cancellable ();

        public ComposerWindow (Gtk.Application app, Gtk.Window parent, ListStore accounts, MailBackend backend,
                               string selected_account, ComposeMode mode, Conversation? conversation = null,
                               Message? source_message = null, Folder? source_account = null) {
            Object (application: app, transient_for: parent, title: "New Message",
                    default_width: 800, default_height: 760, width_request: 360, height_request: 480);
            this.backend = backend;
            this.accounts = accounts;
            var toolbar = new Adw.ToolbarView ();
            var window_title = new Adw.WindowTitle ("New Message", selected_account);
            toolbar.add_top_bar (new Adw.HeaderBar () { title_widget = window_title });
            var fields = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_start = 8, margin_end = 8, margin_top = 6, margin_bottom = 6
            };
            var labels = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            var addresses = new Gtk.StringList (null);
            uint account_position = 0;
            for (uint i = 0; i < accounts.get_n_items (); i++) {
                var account = (Folder) accounts.get_item (i);
                addresses.append (account.account);
                if (source_account != null ? account == source_account : account.account == selected_account) {
                    account_position = i;
                }
            }
            sender = new Gtk.DropDown (addresses, null) { selected = account_position, hexpand = true };
            add_field (fields, labels, "From:", sender);
            var history = ((Application) app).recipients;
            recipient = new RecipientEntry (history);
            cc = new RecipientEntry (history);
            bcc = new RecipientEntry (history);
            subject = new Gtk.Entry () { hexpand = true };
            var to_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            to_box.add_css_class ("linked");
            to_box.append (recipient);
            var show_cc = new Gtk.ToggleButton.with_label ("Cc") { tooltip_text = "Show Cc" };
            var show_bcc = new Gtk.ToggleButton.with_label ("Bcc") { tooltip_text = "Show Bcc" };
            to_box.append (show_cc);
            to_box.append (show_bcc);
            add_field (fields, labels, "To:", to_box);
            var cc_row = add_field (fields, labels, "Cc:", cc);
            var bcc_row = add_field (fields, labels, "Bcc:", bcc);
            show_cc.bind_property ("active", cc_row, "visible", BindingFlags.SYNC_CREATE);
            show_bcc.bind_property ("active", bcc_row, "visible", BindingFlags.SYNC_CREATE);
            add_field (fields, labels, "Subject:", subject);
            toolbar.add_top_bar (fields);

            subject.changed.connect (() => {
                title = subject.text.strip () == "" ? "New Message" : subject.text;
                window_title.title = title;
            });
            string initial_body = "";
            if (conversation != null && conversation.messages.get_n_items () > 0) {
                var message = source_message ?? (Message) conversation.messages.get_item (conversation.messages.get_n_items () - 1);
                if (mode == ComposeMode.DRAFT) {
                    draft_uid = message.uid;
                    draft_account = source_account ?? (Folder) accounts.get_item (account_position);
                    if (message.draft_mime != null) { collect_parts (message.draft_mime); }
                    reply_id = message.in_reply_to;
                    subject.text = message.draft_mime != null ? message.draft_mime.get_subject () ?? "" : conversation.subject;
                    recipient.text = message.recipient;
                    cc.text = message.cc ?? "";
                    bcc.text = message.bcc ?? "";
                    show_cc.active = cc.text != "";
                    show_bcc.active = bcc.text != "";
                    initial_body = message.is_html ? message.body : Markup.escape_text (message.body).replace ("\n", "<br>");
                } else {
                    reply_id = mode == ComposeMode.FORWARD ? null : message.message_id;
                    bool replying = mode == ComposeMode.REPLY || mode == ComposeMode.REPLY_ALL;
                    string prefix = replying ? "Re: " : "Fwd: ";
                    subject.text = conversation.subject.down ().has_prefix (prefix.down ())
                        ? conversation.subject : prefix + conversation.subject;
                    recipient.text = replying ? (message.reply_to ?? message.address) : "";
                    if (mode == ComposeMode.REPLY_ALL) {
                        var additional = new Camel.InternetAddress ();
                        var seen = new HashTable<string, bool> (str_hash, str_equal);
                        seen.insert (message.address.casefold (), true);
                        for (uint i = 0; i < accounts.get_n_items (); i++) { seen.insert (((Folder) accounts.get_item (i)).account.casefold (), true); }
                        var targets = new Camel.InternetAddress ();
                        targets.decode (message.recipient + ", " + (message.cc ?? ""));
                        for (int i = 0; i < targets.length (); i++) {
                            unowned string? name, address;
                            if (targets.get (i, out name, out address) && address != null && !seen.contains (address.casefold ())) {
                                additional.add (name, address);
                                seen.insert (address.casefold (), true);
                            }
                        }
                        cc.text = additional.encode ();
                        show_cc.active = additional.length () > 0;
                    }
                    string quoted = message.is_html ? message.body : Markup.escape_text (message.body).replace ("\n", "<br>");
                    initial_body = "<br><br><blockquote><p>From: %s &lt;%s&gt;<br>To: %s<br>Date: %s<br>Subject: %s</p>%s</blockquote>".printf (
                        Markup.escape_text (message.sender), Markup.escape_text (message.address), Markup.escape_text (message.recipient),
                        Markup.escape_text (message.time_label), Markup.escape_text (conversation.subject), quoted);
                }
            }
            editor = new RichTextEditor (initial_body, conversation != null);
            toolbar.content = editor;
            attachment_box = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE, visible = false,
                margin_start = 8, margin_end = 8, margin_top = 6, margin_bottom = 6
            };
            toolbar.add_bottom_bar (attachment_box);
            foreach (var part in preserved_parts.data) { add_preserved_part (part); }
            attachment_box.visible = preserved_parts.length > 0;
            var actions = new Gtk.ActionBar ();
            var discard = new Gtk.Button.from_icon_name ("user-trash-symbolic") { tooltip_text = "Discard Message" };
            discard.clicked.connect (() => ask_close (true));
            actions.pack_start (discard);
            var attach = new Gtk.Button.from_icon_name ("mail-attachment-symbolic") { tooltip_text = "Attach File" };
            attach.clicked.connect (() => choose_attachments.begin ());
            actions.pack_start (attach);
            var signature = new Gtk.Button.from_icon_name ("document-edit-symbolic") { tooltip_text = "Insert Signature" };
            signature.clicked.connect (() => {
                if (sender.selected != Gtk.INVALID_LIST_POSITION) {
                    editor.insert_signature (((Folder) accounts.get_item (sender.selected)).account);
                }
            });
            actions.pack_start (signature);
            var send_content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            send_content.append (new Gtk.Image.from_icon_name ("mail-send-symbolic"));
            send_content.append (new Gtk.Label ("Send"));
            var send = new Gtk.Button () {
                child = send_content, sensitive = false,
                tooltip_text = "Send Message"
            };
            send_button = send;
            recipient.changed.connect (() => { send.sensitive = recipient.text.strip () != "" && editor.ready && !sending; });
            editor.notify["ready"].connect (() => { send.sensitive = recipient.text.strip () != "" && editor.ready && !sending; });
            send.clicked.connect (() => { submit.begin (); });
            send.add_css_class ("suggested-action");
            send.add_css_class ("pill");
            actions.pack_end (send);
            toolbar.add_bottom_bar (actions);
            content = toolbar;
            initial_fields = field_values ();
            initial_sender = sender.selected;
            close_request.connect (confirm_close);
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((key, code, modifiers) => {
                if (key != Gdk.Key.Escape) { return false; }
                close ();
                return true;
            });
            ((Gtk.Widget) this).add_controller (keys);
            recipient.grab_focus ();
            backend.prepare_recipients.begin ();
        }

        /* ----- Background Submission ----- */
        private async void submit (bool draft = false, bool discard = false) {
            if (sending || sender.selected == Gtk.INVALID_LIST_POSITION) { return; }
            if (discard && draft_uid == null) { discard_confirmed = true; close (); return; }
            sending = true;
            send_button.sensitive = false;
            child.sensitive = false;
            bool background = false, finished = false;
            try {
                var html = discard ? "" : yield editor.export_html ();
                var snapshot = new ComposeSnapshot ((Folder) accounts.get_item (sender.selected), recipient.text, cc.text,
                    bcc.text, subject.text, html, attachments, preserved_parts, reply_id, draft_uid, draft_account);
                backend.begin_background ();
                background = true;
                visible = false;
                if (!draft && !discard) {
                    var settings = ((Application) application).settings;
                    uint seconds = (uint) settings.get_int ("undo-time");
                    if (settings.get_boolean ("undo-send") && seconds > 0) {
                        bool cancelled = false, waiting = true;
                        int64 deadline = get_monotonic_time () + (int64) seconds * 1000000;
                        Adw.Toast? countdown = null;
                        SourceFunc resume = submit.callback;
                        uint timer = Timeout.add (1000, () => {
                            uint remaining = (uint) int64.max (0, (deadline - get_monotonic_time () + 999999) / 1000000);
                            if (remaining == 0) { waiting = false; resume (); return Source.REMOVE; }
                            if (countdown != null) { countdown.title = countdown_text (remaining); }
                            return Source.CONTINUE;
                        });
                        countdown = queued (countdown_text (seconds), new UndoOperation (() => {
                            if (!waiting) { return; }
                            waiting = false;
                            cancelled = true;
                            Source.remove (timer);
                            resume ();
                        }));
                        yield;
                        if (cancelled) { completed ("Sending cancelled"); return; }
                    }
                }
                var job = new Cancellable ();
                queued (discard ? "Deleting draft…" : draft ? "Saving draft…" : "Sending…", null);
                if (discard) {
                    yield backend.discard_previous_draft (snapshot, job);
                    completed ("Draft deleted");
                } else if (draft) {
                    yield backend.save_draft (snapshot, job);
                    completed ("Draft saved");
                } else {
                    bool saved = yield backend.send (snapshot.account, snapshot.to, snapshot.cc, snapshot.bcc, snapshot.subject,
                        snapshot.html, snapshot.files, snapshot.reply_id, job, snapshot.parts);
                    try { yield backend.discard_previous_draft (snapshot, job); }
                    catch (Error error) { completed ("Message sent; the previous draft could not be removed"); }
                    completed (saved ? "Message sent" : "Message sent; a copy could not be saved in Sent");
                }
                finished = true;
            } catch (Error error) {
                present ();
                completed (draft ? "Draft could not be saved" : discard ? "Draft could not be deleted" : "Message could not be sent");
                var dialog = new Adw.AlertDialog (draft ? "Unable to Save Draft" : discard ? "Unable to Delete Draft" : "Unable to Send Message", error.message);
                dialog.add_response ("close", "Keep Editing");
                dialog.present (this);
            } finally {
                sending = false;
                if (!finished) {
                    child.sensitive = true;
                    send_button.sensitive = recipient.text.strip () != "" && editor.ready;
                    present ();
                }
                if (background) { backend.end_background (); }
            }
            if (finished) { discard_confirmed = true; close (); }
        }

        private Gtk.Box add_field (Gtk.Box fields, Gtk.SizeGroup labels, string name, Gtk.Widget input) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var label = new Gtk.Label (name) { xalign = 1, mnemonic_widget = input };
            label.add_css_class ("dim-label");
            labels.add_widget (label);
            input.hexpand = true;
            row.append (label);
            row.append (input);
            fields.append (row);
            return row;
        }

        private async void choose_attachments () {
            try {
                var dialog = new Gtk.FileDialog () { title = "Attach Files" };
                var files = yield dialog.open_multiple (this, cancellable);
                for (uint i = 0; i < files.get_n_items (); i++) {
                    var file = (File) files.get_item (i);
                    bool duplicate = false;
                    for (uint j = 0; j < attachments.length; j++) {
                        if (attachments[j].equal (file)) {
                            duplicate = true;
                            break;
                        }
                    }
                    if (!duplicate) {
                        add_attachment (file);
                    }
                }
            } catch (Error error) {
                if (!(error is Gtk.DialogError.DISMISSED) && !(error is IOError.CANCELLED)) {
                    var dialog = new Adw.AlertDialog ("Unable to Attach Files", error.message);
                    dialog.add_response ("close", "Close");
                    dialog.present (this);
                }
            }
        }

        private void add_attachment (File file) {
            attachments.add (file);
            var chip = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            chip.append (new Gtk.Image.from_icon_name ("mail-attachment-symbolic"));
            chip.append (new Gtk.Label (file.get_basename ()) { ellipsize = Pango.EllipsizeMode.MIDDLE, max_width_chars = 28 });
            var remove = new Gtk.Button.from_icon_name ("window-close-symbolic") { tooltip_text = "Remove Attachment" };
            remove.add_css_class ("flat");
            chip.append (remove);
            var item = new Gtk.FlowBoxChild () { child = chip, tooltip_text = file.get_parse_name () };
            remove.clicked.connect (() => {
                attachments.remove (file);
                attachment_box.remove (item);
                attachment_box.visible = attachments.length > 0 || preserved_parts.length > 0;
            });
            attachment_box.append (item);
            attachment_box.visible = true;
        }

        /* ----- Preserved Draft Attachments ----- */
        private void collect_parts (Camel.MimePart part) {
            if (part.content is Camel.Multipart) {
                var multipart = (Camel.Multipart) part.content;
                for (uint i = 0; i < multipart.get_number (); i++) { collect_parts (multipart.get_part (i)); }
            } else if (part.get_disposition () == "attachment" || part.get_filename () != null || part.get_content_id () != null) {
                preserved_parts.add (part);
            }
        }

        private void add_preserved_part (Camel.MimePart part) {
            var chip = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            chip.append (new Gtk.Image.from_icon_name ("mail-attachment-symbolic"));
            chip.append (new Gtk.Label (part.get_filename () ?? "Inline Image") { ellipsize = Pango.EllipsizeMode.MIDDLE, max_width_chars = 28 });
            var remove = new Gtk.Button.from_icon_name ("window-close-symbolic") { tooltip_text = "Remove Attachment" };
            remove.add_css_class ("flat");
            chip.append (remove);
            var item = new Gtk.FlowBoxChild () { child = chip };
            remove.clicked.connect (() => {
                preserved_parts.remove (part);
                attachments_changed = true;
                attachment_box.remove (item);
                attachment_box.visible = attachments.length > 0 || preserved_parts.length > 0;
            });
            attachment_box.append (item);
        }

        private string[] field_values () {
            return { recipient.text, cc.text, bcc.text, subject.text };
        }

        private bool confirm_close () {
            if (sending) { return true; }
            if (discard_confirmed) {
                return false;
            }
            var current_fields = field_values ();
            bool changed = sender.selected != initial_sender || editor.modified || attachments.length > 0 || attachments_changed;
            for (int i = 0; i < current_fields.length; i++) {
                changed |= current_fields[i] != initial_fields[i];
            }
            if (!changed) {
                return false;
            }
            ask_close (false);
            return true;
        }

        private static string countdown_text (uint seconds) {
            return seconds == 1 ? "Sending in 1 second…" : "Sending in %u seconds…".printf (seconds);
        }

        private void ask_close (bool discard_only) {
            if (sending || close_dialog != null) { return; }
            close_dialog = new Adw.AlertDialog (
                discard_only ? "Permanently Delete This Draft?" : "Save This Draft?",
                discard_only ? "You cannot undo this action or recover your changes."
                    : "Save your message to Drafts, keep editing, or delete this draft.");
            close_dialog.add_response ("cancel", discard_only ? "Cancel" : "Keep Editing");
            close_dialog.add_response ("discard", "Delete Draft");
            close_dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
            if (!discard_only) {
                close_dialog.add_response ("save", "Save Draft");
                close_dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            }
            close_dialog.add_css_class ("draft-confirmation");
            close_dialog.add_css_class ("initial-focus");
            var navigation = new Gtk.EventControllerKey () { propagation_phase = Gtk.PropagationPhase.CAPTURE };
            weak Adw.AlertDialog prompt = close_dialog;
            navigation.key_pressed.connect ((key, code, state) => {
                if (prompt != null && (key == Gdk.Key.Tab || key == Gdk.Key.ISO_Left_Tab)) {
                    prompt.remove_css_class ("initial-focus");
                }
                return false;
            });
            ((Gtk.Widget) close_dialog).add_controller (navigation);
            close_dialog.prefer_wide_layout = false;
            close_dialog.default_response = "cancel";
            close_dialog.close_response = "cancel";
            close_dialog.response.connect ((response) => {
                close_dialog = null;
                if (response == "save") { submit.begin (true); }
                else if (response == "discard") { submit.begin (false, true); }
            });
            close_dialog.present (this);
        }

        protected override void dispose () {
            cancellable.cancel ();
            base.dispose ();
        }
    }
}
