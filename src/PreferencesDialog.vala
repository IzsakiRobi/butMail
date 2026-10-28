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
            Object (title: "Preferences", content_width: 620, content_height: 720);
            pending = new Settings (Application.ID);
            pending.delay ();
            credentials = LogoCredentials.get_default ();
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () {
                title_widget = new Adw.WindowTitle ("Preferences", "butMail"),
                show_start_title_buttons = false, show_end_title_buttons = false
            };
            cancel_button = new Gtk.Button.with_label ("Cancel");
            cancel_button.clicked.connect (() => { pending.revert (); close (); });
            header.pack_start (cancel_button);
            save_button = new Gtk.Button.with_label ("Save");
            save_button.add_css_class ("suggested-action");
            save_button.clicked.connect (() => save.begin ());
            header.pack_end (save_button);
            toolbar.add_top_bar (header);
            var page = new Adw.PreferencesPage ();

            var appearance = new Adw.PreferencesGroup () { title = "Appearance" };
            var scheme = new Adw.ComboRow () {
                title = "Style", model = new Gtk.StringList ({ "System", "Light", "Dark" })
            };
            pending.bind ("color-scheme", scheme, "selected", SettingsBindFlags.DEFAULT);
            appearance.add (scheme);
            page.add (appearance);

            var remote = new Adw.PreferencesGroup () { title = "Remote Content" };
            remote.add (switch_row ("Always Load Remote Images", "always-load-remote-images"));
            var avatars = switch_row ("Show Avatars", "show-avatars");
            remote.add (avatars);
            var logos = switch_row ("Load Avatars and Company Logos", "load-remote-avatars");
            avatars.bind_property ("active", logos, "sensitive", BindingFlags.SYNC_CREATE);
            remote.add (logos);
            page.add (remote);

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
            page.add (key);
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
            reading.add (switch_row ("Run in Background", "run-in-background"));
            page.add (reading);

            var accounts = new Adw.PreferencesGroup () { title = "Accounts and Signatures" };
            var account_status = new Adw.ActionRow () { title = "GNOME Online Accounts", use_markup = false };
            accounts.add (account_status);
            var detected = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
            detected.add_css_class ("boxed-list");
            detected.bind_model (online_accounts.accounts, (item) => {
                var account = (OnlineAccount) item;
                return new Adw.ActionRow () { title = account.identity, subtitle = account.provider, use_markup = false };
            });
            accounts.add (detected);
            var account_buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { margin_top = 12, homogeneous = true };
            var signatures = new Gtk.Button.with_label ("Edit Signatures…");
            signatures.clicked.connect (() => { new SignatureDialog (pending).present (this); });
            account_buttons.append (signatures);
            var account_settings = new Gtk.Button.with_label ("Account Settings…");
            account_settings.clicked.connect (() => OnlineAccounts.open_settings.begin (this));
            account_buttons.append (account_settings);
            accounts.add (account_buttons);
            ulong accounts_handler = online_accounts.changed.connect (() => update_accounts (online_accounts, account_status));
            update_accounts (online_accounts, account_status);
            page.add (accounts);
            toolbar.content = page;
            child = toolbar;
            closed.connect (() => {
                finished = true;
                pending.revert ();
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

        private void update_accounts (OnlineAccounts accounts, Adw.ActionRow row) {
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
