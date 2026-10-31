/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class FolderNameDialog : Adw.AlertDialog {
        public signal void name_chosen (string name);

        public FolderNameDialog (Folder parent, Folder? existing) {
            Object (heading: existing == null ? (parent.is_account ? "New Folder" : "New Subfolder") : "Rename Folder");
            var entry = new Adw.EntryRow () { title = "Folder Name", activates_default = true, text = existing != null ? existing.name : "" };
            var group = new Adw.PreferencesGroup ();
            group.add (entry);
            var validation = new Gtk.Label ("") { wrap = true, xalign = 0 };
            validation.add_css_class ("error");
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            content.append (group);
            content.append (validation);
            extra_child = content;
            add_responses ("cancel", "Cancel", "apply", existing == null ? "Create" : "Rename", null);
            close_response = "cancel";
            default_response = "apply";
            set_response_appearance ("apply", Adw.ResponseAppearance.SUGGESTED);
            set_response_enabled ("apply", false);
            entry.changed.connect (() => {
                string name = entry.text.strip ();
                var error = MailOperations.validate_name (parent, name, existing);
                validation.label = name == "" ? "" : error ?? "";
                set_response_enabled ("apply", error == null && (existing == null || name != existing.name));
            });
            response.connect ((id) => { if (id == "apply") { name_chosen (entry.text.strip ()); } });
        }
    }
}
