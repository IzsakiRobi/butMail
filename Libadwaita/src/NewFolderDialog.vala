/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class NewFolderDialog : Adw.AlertDialog {
        public signal void folder_created (Folder account, string name);
        private ListStore accounts;
        private Adw.ComboRow account;
        private Adw.EntryRow name_entry;
        private Gtk.Label validation;

        public NewFolderDialog (ListStore accounts, Folder selected_account) {
            Object (heading: "New Folder", body: "Choose an account for the new folder.");
            this.accounts = accounts;
            var names = new Gtk.StringList (null);
            uint selected = 0;
            for (uint i = 0; i < accounts.get_n_items (); i++) {
                var item = (Folder) accounts.get_item (i);
                names.append (item.account);
                if (item == selected_account) {
                    selected = i;
                }
            }
            account = new Adw.ComboRow () { title = "Account", model = names, selected = selected };
            name_entry = new Adw.EntryRow () { title = "Folder Name", activates_default = true };
            var group = new Adw.PreferencesGroup ();
            group.add (account);
            group.add (name_entry);
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            content.append (group);
            validation = new Gtk.Label ("") { xalign = 0, wrap = true };
            validation.add_css_class ("error");
            content.append (validation);
            extra_child = content;
            add_responses ("cancel", "Cancel", "create", "Create", null);
            default_response = "create";
            close_response = "cancel";
            set_response_appearance ("create", Adw.ResponseAppearance.SUGGESTED);
            set_response_enabled ("create", false);
            name_entry.changed.connect (validate);
            account.notify["selected"].connect (validate);
            response.connect ((id) => {
                if (id == "create") {
                    folder_created ((Folder) accounts.get_item (account.selected), name_entry.text.strip ());
                }
            });
        }

        private void validate () {
            string name = name_entry.text.strip ();
            var parent = (Folder) accounts.get_item (account.selected);
            var error = MailOperations.validate_name (parent, name);
            validation.label = name == "" ? "" : error ?? "";
            set_response_enabled ("create", error == null);
        }
    }
}
