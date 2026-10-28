/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class DraftDialog : Adw.Dialog {
        public signal void response (string response);
        private bool answered;

        public DraftDialog (bool discard_only) {
            Object (title: discard_only ? "Delete Draft" : "Save Draft", content_width: 620,
                follows_content_size: true, presentation_mode: Adw.DialogPresentationMode.FLOATING);
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 28) {
                margin_top = 28, margin_bottom = 24, margin_start = 24, margin_end = 24
            };
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            var icon = new Gtk.Image.from_icon_name ("text-x-generic-symbolic") { pixel_size = 48, valign = Gtk.Align.START };
            icon.add_css_class ("dim-label");
            heading.append (icon);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { hexpand = true };
            var title = new Gtk.Label (discard_only ? "Permanently Delete This Draft?" : "Save This Draft?") {
                xalign = 0, wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR
            };
            title.add_css_class ("title-2");
            text.append (title);
            text.append (new Gtk.Label (discard_only
                ? "You cannot undo this action or recover your changes."
                : "Save your message to Drafts, keep editing, or delete this draft.") {
                xalign = 0, wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR
            });
            heading.append (text);
            content.append (heading);
            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var delete = new Gtk.Button.with_label ("Delete Draft") { width_request = 112 };
            delete.add_css_class ("destructive-action");
            delete.clicked.connect (() => choose ("discard"));
            var edit = new Gtk.Button.with_label (discard_only ? "Cancel" : "Edit") { width_request = 80 };
            edit.clicked.connect (() => choose ("cancel"));
            if (discard_only) {
                actions.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });
                actions.append (edit);
                actions.append (delete);
                default_widget = edit;
            } else {
                actions.append (delete);
                actions.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });
                actions.append (edit);
                var save = new Gtk.Button.with_label ("Save") { width_request = 80 };
                save.add_css_class ("suggested-action");
                save.clicked.connect (() => choose ("save"));
                actions.append (save);
                default_widget = save;
            }
            content.append (actions);
            child = content;
            closed.connect (() => { if (!answered) { answered = true; response ("cancel"); } });
        }

        private void choose (string result) {
            if (answered) { return; }
            answered = true;
            force_close ();
            response (result);
        }
    }
}
