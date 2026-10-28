/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class RichTextEditor : Gtk.Box {
        public bool modified { get; private set; }
        public bool ready { get; private set; }
        private WebKit.WebView view;
        private Gtk.Overlay editor_area;
        private Cancellable cancellable = new Cancellable ();
        private ulong theme_handler;
        private Gtk.EmojiChooser? emoji_chooser;
        private bool opening_emoji;
        private const string WORLD = "butmail-editor";

        public RichTextEditor (string initial_text, bool is_html = false) {
            Object (orientation: Gtk.Orientation.VERTICAL, vexpand: true);
            var manager = new WebKit.UserContentManager ();
            manager.register_script_message_handler ("changed", WORLD);
            manager.script_message_received["changed"].connect ((value) => { modified = value.to_boolean (); });
            try {
                var script = resources_lookup_data (Application.RESOURCE_PATH + "/editor.js", ResourceLookupFlags.NONE);
                manager.add_script (new WebKit.UserScript.for_world (
                    (string) script.get_data (), WebKit.UserContentInjectedFrames.TOP_FRAME,
                    WebKit.UserScriptInjectionTime.END, WORLD, null, null
                ));
            } catch (Error error) {
                warning ("Unable to load editor script: %s", error.message);
            }
            view = (WebKit.WebView) Object.new (typeof (WebKit.WebView),
                "network-session", new WebKit.NetworkSession.ephemeral (), "user-content-manager", manager);
            view.set_background_color (Gdk.RGBA () { alpha = 0 });
            view.editable = true;
            view.vexpand = true;
            view.get_settings ().enable_javascript_markup = false;
            var emoji_keys = new Gtk.EventControllerKey () { propagation_phase = Gtk.PropagationPhase.CAPTURE };
            emoji_keys.key_pressed.connect ((key, code, modifiers) => {
                var relevant = modifiers & Gtk.accelerator_get_default_mod_mask ();
                if (ready && relevant == Gdk.ModifierType.CONTROL_MASK && (key == Gdk.Key.period || key == Gdk.Key.semicolon)) {
                    show_emoji.begin ();
                    return true;
                }
                return false;
            });
            ((Gtk.Widget) view).add_controller (emoji_keys);
            view.decide_policy.connect ((decision, type) => {
                if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
                    var navigation = (WebKit.NavigationPolicyDecision) decision;
                    if (navigation.navigation_action.get_navigation_type () == WebKit.NavigationType.LINK_CLICKED) {
                        decision.ignore ();
                        return true;
                    }
                }
                return false;
            });
            var tools = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_start = 8, margin_end = 8, margin_top = 6, margin_bottom = 6, sensitive = false
            };
            var formatting = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            formatting.add_css_class ("linked");
            formatting.append (format_button ("format-text-bold-symbolic", "Bold", "Bold", WebKit.EditorTypingAttributes.BOLD));
            formatting.append (format_button ("format-text-italic-symbolic", "Italic", "Italic", WebKit.EditorTypingAttributes.ITALIC));
            formatting.append (format_button ("format-text-underline-symbolic", "Underline", "Underline", WebKit.EditorTypingAttributes.UNDERLINE));
            formatting.append (format_button ("format-text-strikethrough-symbolic", "Strikethrough", "Strikethrough", WebKit.EditorTypingAttributes.STRIKETHROUGH));
            tools.append (formatting);
            var clear = new Gtk.Button.with_label ("Fₓ") { tooltip_text = "Remove Formatting", focus_on_click = false };
            clear.clicked.connect (() => { execute ("RemoveFormat"); execute ("Unlink"); });
            tools.append (clear);
            var font = tool_button ("font-select-symbolic", "Font");
            font.clicked.connect (() => choose_font.begin ());
            tools.append (font);
            var link = tool_button ("insert-link-symbolic", "Insert Link");
            link.clicked.connect (insert_link);
            tools.append (link);
            var image = tool_button ("insert-image-symbolic", "Insert Image");
            image.clicked.connect (() => insert_image.begin ());
            tools.append (image);
            append (tools);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            var loading = new LoadingIndicator ();
            editor_area = new Gtk.Overlay () { child = view, vexpand = true };
            editor_area.add_css_class ("butmail-editor-surface");
            editor_area.add_overlay (loading);
            append (editor_area);
            view.load_changed.connect ((event) => {
                if (event == WebKit.LoadEvent.FINISHED) {
                    tools.sensitive = true;
                    ready = true;
                    update_theme ();
                    loading.visible = false;
                }
            });
            update_theme ();
            theme_handler = Adw.StyleManager.get_default ().notify["dark"].connect (update_theme);
            try {
                var template = resources_lookup_data (Application.RESOURCE_PATH + "/editor.html", ResourceLookupFlags.NONE);
                string content = is_html ? initial_text : Markup.escape_text (initial_text).replace ("\n", "<br>") + "<br>";
                view.load_html (((string) template.get_data ()).replace ("@CONTENT@", content).replace ("@THEME@", Adw.StyleManager.get_default ().dark ? "data-dark" : ""), "about:blank");
            } catch (Error error) {
                warning ("Unable to load editor document: %s", error.message);
            }
        }

        private Gtk.Button tool_button (string icon, string tooltip) {
            return new Gtk.Button.from_icon_name (icon) { tooltip_text = tooltip, focus_on_click = false };
        }

        private Gtk.ToggleButton format_button (string icon, string tooltip, string command, WebKit.EditorTypingAttributes attribute) {
            var button = new Gtk.ToggleButton () { icon_name = icon, tooltip_text = tooltip, focus_on_click = false };
            button.clicked.connect (() => execute (command));
            view.get_editor_state ().notify["typing-attributes"].connect (() => {
                button.active = (view.get_editor_state ().typing_attributes & attribute) != 0;
            });
            return button;
        }

        private void execute (string command, string? argument = null) {
            view.grab_focus ();
            if (argument == null) {
                view.execute_editing_command (command);
            } else {
                view.execute_editing_command_with_argument (command, argument);
            }
        }

        /* ----- Keyboard Emoji Insertion ----- */
        private async void show_emoji () {
            if (opening_emoji || (emoji_chooser != null && emoji_chooser.visible)) { return; }
            opening_emoji = true;
            var location = Gdk.Rectangle () { x = 8, y = 8, width = 1, height = 20 };
            try {
                var rect = yield view.evaluate_javascript (
                    "(() => { const s = window.getSelection(); if (!s.rangeCount) return [8, 8, 20]; " +
                    "const r = s.getRangeAt(0).getBoundingClientRect(); return [r.x, r.y, r.height]; })()",
                    -1, WORLD, null, cancellable);
                location.x = int.max (0, int.min ((int) rect.object_get_property_at_index (0).to_double (), view.get_width () - 1));
                location.y = int.max (0, int.min ((int) rect.object_get_property_at_index (1).to_double (), view.get_height () - 1));
                location.height = int.max (1, (int) rect.object_get_property_at_index (2).to_double ());
            } catch (Error error) {
                if (error is IOError.CANCELLED) { opening_emoji = false; return; }
            }
            if (emoji_chooser == null) {
                emoji_chooser = new Gtk.EmojiChooser ();
                emoji_chooser.set_parent (view);
                emoji_chooser.emoji_picked.connect ((emoji) => {
                    emoji_chooser.popdown ();
                    execute ("InsertText", emoji);
                });
                emoji_chooser.closed.connect (() => {
                    if (!cancellable.is_cancelled () && view.get_mapped ()) { view.grab_focus (); }
                });
            }
            emoji_chooser.pointing_to = location;
            emoji_chooser.popup ();
            opening_emoji = false;
        }

        private async void choose_font () {
            try {
                var dialog = new Gtk.FontDialog () { title = "Choose Font" };
                var family = yield dialog.choose_family ((Gtk.Window) get_root (), null, cancellable);
                execute ("FontName", family.get_name ());
            } catch (Error error) {
                if (!(error is Gtk.DialogError.DISMISSED) && !(error is IOError.CANCELLED)) {
                    show_error (error.message);
                }
            }
        }

        private void insert_link () {
            var dialog = new Adw.AlertDialog ("Insert Link", null);
            var fields = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var address = new Gtk.Entry () { placeholder_text = "https://example.com", input_purpose = Gtk.InputPurpose.URL };
            var text = new Gtk.Entry () { placeholder_text = "Link text (optional)" };
            fields.append (address);
            fields.append (text);
            dialog.extra_child = fields;
            dialog.add_responses ("cancel", "Cancel", "insert", "Insert", null);
            dialog.default_response = "insert";
            dialog.close_response = "cancel";
            dialog.set_response_appearance ("insert", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_response_enabled ("insert", false);
            address.changed.connect (() => {
                string? scheme = Uri.peek_scheme (address.text.strip ());
                dialog.set_response_enabled ("insert", scheme == "https" || scheme == "http" || scheme == "mailto");
            });
            dialog.response.connect ((response) => {
                if (response != "insert") {
                    return;
                }
                string url = address.text.strip ();
                if (text.text == "") {
                    execute ("CreateLink", url);
                } else {
                    execute ("InsertHTML", "<a href=\"%s\">%s</a>".printf (Markup.escape_text (url), Markup.escape_text (text.text)));
                }
            });
            dialog.present (this);
        }

        private async void insert_image () {
            try {
                var dialog = new Gtk.FileDialog () { title = "Insert Image" };
                var filter = new Gtk.FileFilter () { name = "Images" };
                filter.add_mime_type ("image/png");
                filter.add_mime_type ("image/jpeg");
                filter.add_mime_type ("image/webp");
                filter.add_mime_type ("image/gif");
                var filters = new ListStore (typeof (Gtk.FileFilter));
                filters.append (filter);
                dialog.filters = filters;
                dialog.default_filter = filter;
                var file = yield dialog.open ((Gtk.Window) get_root (), cancellable);
                var info = yield file.query_info_async (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE, Priority.DEFAULT, cancellable);
                if (info.get_size () > 20 * 1024 * 1024) {
                    show_error ("Choose an image smaller than 20 MB.");
                    return;
                }
                uint8[] data;
                yield file.load_contents_async (cancellable, out data, null);
                var texture = Gdk.Texture.from_bytes (new Bytes (data));
                var png = texture.save_to_png_bytes ();
                execute ("InsertImage", "data:image/png;base64," + Base64.encode (png.get_data ()));
            } catch (Error error) {
                if (!(error is Gtk.DialogError.DISMISSED) && !(error is IOError.CANCELLED)) {
                    show_error (error.message);
                }
            }
        }

        public async string export_html () throws Error {
            var result = yield view.evaluate_javascript ("document.body.innerHTML", -1, WORLD, null, cancellable);
            return result.to_string ();
        }

        public void insert_signature (string account) {
            var settings = new Settings (Application.ID);
            string saved = Signatures.get_html (settings, account);
            if (saved != "") {
                execute ("InsertHTML", "<br><br>" + saved);
                return;
            }
            var dialog = new Adw.AlertDialog ("Insert Signature", null);
            var signature = new Gtk.TextView () { wrap_mode = Gtk.WrapMode.WORD_CHAR, height_request = 120 };
            dialog.extra_child = new Gtk.Frame (null) { child = signature };
            dialog.add_responses ("cancel", "Cancel", "insert", "Insert", null);
            dialog.default_response = "insert";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "insert" && signature.buffer.text != "") {
                    execute ("InsertHTML", "<br><br>" + Markup.escape_text (signature.buffer.text).replace ("\n", "<br>"));
                }
            });
            dialog.present (this);
        }

        private void show_error (string message) {
            var dialog = new Adw.AlertDialog ("Unable to Complete Action", message);
            dialog.add_response ("close", "Close");
            dialog.present (this);
        }

        private void update_theme () {
            bool dark = Adw.StyleManager.get_default ().dark;
            if (dark) { editor_area.add_css_class ("dark"); }
            else { editor_area.remove_css_class ("dark"); }
            if (!ready) { return; }
            view.evaluate_javascript.begin ("document.documentElement.toggleAttribute('data-dark', " + (dark ? "true" : "false") + ");",
                -1, WORLD, null, cancellable, (obj, result) => {
                    try {
                        view.evaluate_javascript.end (result);
                    } catch (Error error) {
                        if (!(error is IOError.CANCELLED)) {
                            warning ("Unable to update editor appearance: %s", error.message);
                        }
                    }
                });
        }

        protected override void dispose () {
            cancellable.cancel ();
            if (emoji_chooser != null && emoji_chooser.get_parent () != null) { emoji_chooser.unparent (); }
            if (theme_handler != 0) {
                Adw.StyleManager.get_default ().disconnect (theme_handler);
                theme_handler = 0;
            }
            base.dispose ();
        }
    }
}
