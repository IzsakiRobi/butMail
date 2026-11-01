/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    public class SignatureDialog : Adw.Dialog {
        public SignatureDialog (Signatures signatures, Signature? signature = null) {
            Object (title: signature != null ? "Edit Signature" : "New Signature", content_width: 640, content_height: 460);
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () {
                show_start_title_buttons = false, show_end_title_buttons = false
            };
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (() => close ());
            header.pack_start (cancel);
            var save = new Gtk.Button.with_label ("Save") { sensitive = false };
            save.add_css_class ("suggested-action");
            header.pack_end (save);
            toolbar.add_top_bar (header);
            var name = new Gtk.Entry () {
                placeholder_text = "Signature name", text = signature != null ? signature.name : "",
                margin_start = 12, margin_end = 12, margin_top = 8, margin_bottom = 8
            };
            toolbar.add_top_bar (name);
            var editor = new RichTextEditor (signature != null ? signature.html : "", true);
            editor.notify["ready"].connect (() => { save.sensitive = editor.ready && name.text.strip () != ""; });
            name.changed.connect (() => { save.sensitive = editor.ready && name.text.strip () != ""; });
            save.clicked.connect (() => {
                save.sensitive = false;
                cancel.sensitive = false;
                can_close = false;
                save_signature.begin (signatures, signature, name.text.strip (), editor, save, cancel);
            });
            toolbar.content = editor;
            child = toolbar;
        }

        private async void save_signature (Signatures signatures, Signature? signature, string name,
                                           RichTextEditor editor, Gtk.Button save, Gtk.Button cancel) {
            try {
                string html = yield editor.export_html ();
                yield signatures.save (signature, name, html);
                can_close = true;
                close ();
            } catch (Error error) {
                can_close = true;
                save.sensitive = true;
                cancel.sensitive = true;
                var dialog = new Adw.AlertDialog ("Unable to Save Signature", error.message);
                dialog.add_response ("close", "Close");
                dialog.present (this);
            }
        }
    }
}
