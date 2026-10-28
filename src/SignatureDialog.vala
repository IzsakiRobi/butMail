/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class SignatureDialog : Adw.Dialog {
        public SignatureDialog (Settings pending) {
            Object (title: "Signatures", content_width: 720, content_height: 500);
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () {
                title_widget = new Adw.WindowTitle ("Default Signature", "Applied when Preferences are saved"),
                show_start_title_buttons = false, show_end_title_buttons = false
            };
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (() => close ());
            header.pack_start (cancel);
            var save = new Gtk.Button.with_label ("Apply") { sensitive = false };
            save.add_css_class ("suggested-action");
            header.pack_end (save);
            toolbar.add_top_bar (header);
            var editor = new RichTextEditor (pending.get_string ("signature-html"), true);
            editor.bind_property ("ready", save, "sensitive", BindingFlags.SYNC_CREATE);
            save.clicked.connect (() => {
                save.sensitive = false;
                editor.export_html.begin ((obj, result) => {
                    try {
                        pending.set_string ("signature-html", editor.export_html.end (result));
                        close ();
                    } catch (Error error) {
                        save.sensitive = true;
                        var dialog = new Adw.AlertDialog ("Unable to Save Signature", error.message);
                        dialog.add_response ("close", "Close");
                        dialog.present (this);
                    }
                });
            });
            toolbar.content = editor;
            child = toolbar;
        }
    }
}
