/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class PreferencesDialog : Adw.Dialog {
        private Settings pending;
        private LogoCredentials credentials;
        private Adw.PasswordEntryRow key_entry;
        private Gtk.Button key_save;
        private Gtk.Button key_clear;
        private Gtk.Button save_button;
        private Gtk.Button cancel_button;
        private Gtk.Label key_status;
        private bool key_dirty;
        private bool filling_key;
        private bool busy;
        private bool finished;

        public PreferencesDialog (OnlineAccounts online_accounts) {
            Object (title: "Preferences", content_width: 680, content_height: 720);
            pending = new Settings (Application.ID);
            pending.delay ();
            var app = (Application) GLib.Application.get_default ();
            pending.changed["color-scheme"].connect (() => app.preview_color_scheme (pending.get_uint ("color-scheme")));
            credentials = LogoCredentials.get_default ();
            var toolbar = new Adw.ToolbarView ();
            var pages = new Adw.ViewStack ();
            var switcher = new Adw.ViewSwitcher () { stack = pages, policy = Adw.ViewSwitcherPolicy.WIDE };
            var header = new Adw.HeaderBar () {
                title_widget = switcher, centering_policy = Adw.CenteringPolicy.STRICT,
                show_start_title_buttons = false, show_end_title_buttons = false
            };
            cancel_button = new Gtk.Button.with_label ("Cancel");
            cancel_button.clicked.connect (() => { pending.revert (); close (); });
            header.pack_start (cancel_button);
            save_button = new Gtk.Button.with_label ("Save");
            save_button.add_css_class ("suggested-action");
            save_button.clicked.connect (() => save.begin ());
            header.pack_end (save_button);
            var header_buttons = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            header_buttons.add_widget (cancel_button);
            header_buttons.add_widget (save_button);
            toolbar.add_top_bar (header);
            var view_page = new Adw.PreferencesPage ();
            var reading_page = new Adw.PreferencesPage ();
            var accounts_page = new Adw.PreferencesPage ();
            pages.add_titled_with_icon (view_page, "view", "View", "preferences-desktop-display-symbolic");
            pages.add_titled_with_icon (reading_page, "reading", "Reading", "mail-read-symbolic");
            pages.add_titled_with_icon (accounts_page, "accounts", "Acc/Sys", "avatar-default-symbolic");

            var appearance = new Adw.PreferencesGroup () { title = "Appearance" };
            var scheme = new Adw.ComboRow () {
                title = "Style", model = new Gtk.StringList ({ "System", "Light", "Dark" })
            };
            pending.bind ("color-scheme", scheme, "selected", SettingsBindFlags.DEFAULT);
            appearance.add (scheme);
            view_page.add (appearance);

            var avatars = switch_row ("Show Avatars", "show-avatars");
            appearance.add (avatars);
            var logos = switch_row ("Load Avatars and Company Logos", "load-remote-avatars");
            avatars.bind_property ("active", logos, "sensitive", BindingFlags.SYNC_CREATE);
            appearance.add (logos);
            appearance.add (switch_row ("Always Load Remote Images", "always-load-remote-images"));

            var key = new Adw.PreferencesGroup () {
                title = "Logo.dev API Key",
                description = "Stored in the system keyring."
            };
            key_entry = new Adw.PasswordEntryRow () { title = "Publishable key beginning with pk_", sensitive = false };
            key_save = new Gtk.Button.with_label ("Save") { valign = Gtk.Align.CENTER, sensitive = false };
            key_clear = new Gtk.Button.with_label ("Clear") { valign = Gtk.Align.CENTER, sensitive = false };
            key_entry.add_suffix (key_save);
            key_entry.add_suffix (key_clear);
            key.add (key_entry);
            key_status = new Gtk.Label ("") { xalign = 0, wrap = true, visible = false, margin_top = 8 };
            key_status.add_css_class ("caption");
            key_status.add_css_class ("error");
            key.add (key_status);
            key.add (new Gtk.Label ("Create a free <a href=\"https://logo.dev\">Logo.dev</a> account for high-resolution company logos.") {
                use_markup = true, xalign = 0, wrap = true, margin_top = 8
            });
            var sources = new Adw.PreferencesGroup () { title = "Logo Sources" };
            var show_sources = new Adw.ExpanderRow () { title = "Sources" };
            key.margin_top = 12;
            key.margin_bottom = 12;
            key.margin_start = 12;
            key.margin_end = 12;
            show_sources.add_row (key);
            sources.add (show_sources);
            view_page.add (sources);
            key_entry.changed.connect (() => {
                if (!filling_key) {
                    key_dirty = true;
                    update_key_controls ();
                    key_status.visible = false;
                }
            });
            key_save.clicked.connect (() => save_key.begin ());
            key_clear.clicked.connect (() => {
                key_entry.text = "";
                key_dirty = true;
                save_key.begin ();
            });
            ulong key_handler = credentials.changed.connect (fill_key);
            credentials.refresh.begin ();
            fill_key ();

            var reading = new Adw.PreferencesGroup () { title = "Reading and Undo" };
            reading.add (delay_row ("Mark as Read After", "mark-read-delay"));
            reading.add (delay_row ("Undo Time", "undo-time"));
            reading.add (switch_row ("Undo for Send", "undo-send"));
            reading.add (switch_row ("Undo for Delete", "undo-delete"));
            reading_page.add (reading);

            var accounts = new Adw.PreferencesGroup () { title = "Accounts and Signatures" };
            var account_status = new Adw.ActionRow () { title = "GNOME Online Accounts", use_markup = false };
            accounts.add (account_status);
            var detected = new GenericArray<Adw.ActionRow> ();
            var account_settings = new Gtk.Button.with_label ("Open Online Accounts…") { margin_top = 12 };
            account_settings.clicked.connect (() => OnlineAccounts.open_settings.begin (this));
            accounts.add (account_settings);
            accounts_page.add (accounts);

            var signatures = new Adw.PreferencesGroup () { title = "Signatures" };
            var signature_rows = new GenericArray<Adw.ActionRow> ();
            var new_signature = new Gtk.Button.with_label ("New…") { valign = Gtk.Align.CENTER };
            signatures.header_suffix = new_signature;
            new_signature.clicked.connect (() => { new SignatureDialog (app.signatures).present (this); });
            ulong signatures_handler = app.signatures.changed.connect (() => {
                update_signatures (online_accounts, signatures, signature_rows);
                new_signature.sensitive = app.signatures.ready;
            });
            ulong accounts_handler = online_accounts.changed.connect (() => {
                update_accounts (online_accounts, account_status, accounts, detected);
                update_signatures (online_accounts, signatures, signature_rows);
            });
            update_accounts (online_accounts, account_status, accounts, detected);
            update_signatures (online_accounts, signatures, signature_rows);
            new_signature.sensitive = app.signatures.ready;
            accounts_page.add (signatures);

            var system = new Adw.PreferencesGroup () { title = "System" };
            system.add (switch_row ("Run in Background", "run-in-background"));
            accounts_page.add (system);
            toolbar.content = pages;
            child = toolbar;
            closed.connect (() => {
                finished = true;
                pending.revert ();
                app.preview_color_scheme (app.settings.get_uint ("color-scheme"));
                app.signatures.disconnect (signatures_handler);
                credentials.disconnect (key_handler);
                online_accounts.disconnect (accounts_handler);
            });
        }

        private Adw.SwitchRow switch_row (string title, string key) {
            var row = new Adw.SwitchRow () { title = title };
            pending.bind (key, row, "active", SettingsBindFlags.DEFAULT);
            return row;
        }

        private Adw.ActionRow delay_row (string title, string key) {
            var row = new Adw.ActionRow () { title = title };
            var adjustment = new Gtk.Adjustment (0, 0, 5, 1, 1, 0);
            pending.bind (key, adjustment, "value", SettingsBindFlags.DEFAULT);
            var scale = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, adjustment) {
                draw_value = false, digits = 0, round_digits = 0, width_request = 150, valign = Gtk.Align.CENTER
            };
            for (int i = 0; i <= 5; i++) {
                scale.add_mark (i, Gtk.PositionType.BOTTOM, null);
            }
            var value = new Gtk.Label ("%d s".printf ((int) adjustment.value)) { width_chars = 3 };
            adjustment.value_changed.connect (() => { value.label = "%d s".printf ((int) adjustment.value); });
            row.add_suffix (scale);
            row.add_suffix (value);
            return row;
        }

        private void update_accounts (OnlineAccounts accounts, Adw.ActionRow row,
                                      Adw.PreferencesGroup group, GenericArray<Adw.ActionRow> detected) {
            while (detected.length > 0) {
                group.remove (detected[0]);
                detected.remove_index (0);
            }
            for (uint i = 0; i < accounts.accounts.get_n_items (); i++) {
                var account = (OnlineAccount) accounts.accounts.get_item (i);
                var item = new Adw.ActionRow () {
                    title = account.identity, subtitle = account.provider, use_markup = false
                };
                group.add (item);
                detected.add (item);
            }
            if (!accounts.ready) {
                row.subtitle = "Checking for mail accounts…";
            } else if (accounts.error_message != null) {
                row.subtitle = "Unable to read Online Accounts. Open Account Settings to check the service.";
            } else {
                uint count = accounts.accounts.get_n_items ();
                row.subtitle = count == 1
                    ? "1 mail account found."
                    : "%u mail accounts found.".printf (count);
            }
        }

        private void update_signatures (OnlineAccounts accounts, Adw.PreferencesGroup group,
                                        GenericArray<Adw.ActionRow> rows) {
            var signatures = ((Application) GLib.Application.get_default ()).signatures;
            while (rows.length > 0) {
                group.remove (rows[0]);
                rows.remove_index (0);
            }
            group.description = signatures.error_message ?? (!signatures.ready ? "Loading signatures…" : null);
            for (uint i = 0; i < signatures.items.get_n_items (); i++) {
                var signature = (Signature) signatures.items.get_item (i);
                var row = new Adw.ActionRow () { title = signature.name, use_markup = false };
                var edit = new Gtk.Button.with_label ("Edit…") { valign = Gtk.Align.CENTER };
                edit.clicked.connect (() => { new SignatureDialog (signatures, signature).present (this); });
                var remove = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                    tooltip_text = "Delete Signature", valign = Gtk.Align.CENTER
                };
                remove.clicked.connect (() => remove_signature (signatures, signature));
                row.add_suffix (edit);
                row.add_suffix (remove);
                row.activatable_widget = edit;
                group.add (row);
                rows.add (row);
            }
            for (uint i = 0; i < accounts.accounts.get_n_items (); i++) {
                var account = (OnlineAccount) accounts.accounts.get_item (i);
                var names = new Gtk.StringList ({ "None" });
                string[] ids = { "none" };
                for (uint j = 0; j < signatures.items.get_n_items (); j++) {
                    var signature = (Signature) signatures.items.get_item (j);
                    names.append (signature.name);
                    ids += signature.id;
                }
                uint selected = 0;
                string current = signatures.default_id (pending, account.identity);
                for (uint j = 0; j < ids.length; j++) { if (ids[j] == current) { selected = j; } }
                var row = new Adw.ComboRow () {
                    title = account.identity, subtitle = "Default signature", use_markup = false,
                    model = names, selected = selected, sensitive = signatures.ready
                };
                row.notify["selected"].connect (() => {
                    if (row.selected < ids.length) { Signatures.set_default (pending, account.identity, ids[row.selected]); }
                });
                group.add (row);
                rows.add (row);
            }
        }

        private void remove_signature (Signatures signatures, Signature signature) {
            var dialog = new Adw.AlertDialog ("Delete Signature?", signature.name);
            dialog.add_responses ("cancel", "Cancel", "delete", "Delete", null);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((response) => {
                if (response != "delete") { return; }
                signatures.remove.begin (signature, (obj, result) => {
                    try { signatures.remove.end (result); }
                    catch (Error error) {
                        var failure = new Adw.AlertDialog ("Unable to Delete Signature", error.message);
                        failure.add_response ("close", "Close");
                        failure.present (this);
                    }
                });
            });
            dialog.present (this);
        }

        private void fill_key () {
            if (finished) {
                return;
            }
            if (credentials.ready && !key_dirty) {
                filling_key = true;
                key_entry.text = credentials.key ?? "";
                filling_key = false;
                key_status.visible = false;
            }
            update_key_controls ();
        }

        private void update_key_controls () {
            key_entry.sensitive = credentials.ready && !busy;
            key_save.sensitive = credentials.ready && !busy && key_dirty;
            key_clear.sensitive = credentials.ready && !busy && (credentials.key != null || key_entry.text != "");
        }

        private void set_busy (bool value) {
            busy = value;
            can_close = !value;
            save_button.sensitive = !value;
            cancel_button.sensitive = !value;
            update_key_controls ();
        }

        private async bool save_key () {
            set_busy (true);
            bool success = false;
            try {
                yield credentials.save (key_entry.text);
                key_dirty = false;
                fill_key ();
                key_status.visible = false;
                success = true;
            } catch (Error error) {
                key_status.label = error.message;
                key_status.visible = true;
            }
            set_busy (false);
            return success;
        }

        private async void save () {
            if (key_dirty && !yield save_key ()) {
                return;
            }
            pending.apply ();
            close ();
        }
    }
}
