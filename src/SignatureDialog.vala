/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class SignatureDialog : Adw.Dialog {
        public SignatureDialog (Settings pending, string account) {
            Object (title: "Signatures", content_width: 720, content_height: 500);
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () {
                title_widget = new Adw.WindowTitle ("Signature", account),
                show_start_title_buttons = false, show_end_title_buttons = false
            };
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (() => close ());
            header.pack_start (cancel);
            var save = new Gtk.Button.with_label ("Apply") { sensitive = false };
            save.add_css_class ("suggested-action");
            header.pack_end (save);
            toolbar.add_top_bar (header);
            var editor = new RichTextEditor (Signatures.get_html (pending, account), true);
            editor.bind_property ("ready", save, "sensitive", BindingFlags.SYNC_CREATE);
            save.clicked.connect (() => {
                save.sensitive = false;
                editor.export_html.begin ((obj, result) => {
                    try {
                        string html = editor.export_html.end (result);
                        if (html.replace ("<br>", "").replace ("<div>", "").replace ("</div>", "").strip () == "") { html = ""; }
                        Signatures.set_html (pending, account, html);
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
