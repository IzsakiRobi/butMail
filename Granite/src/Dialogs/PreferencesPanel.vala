/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.PreferencesPanel : Granite.Dialog {
    private Gtk.Switch remote_images;
    private Gtk.Switch remote_logos;
    private Gtk.Switch show_avatars;
    private Gtk.Switch undo_send;
    private Gtk.Switch undo_delete;
    private Gtk.Switch background;
    private Gtk.Scale read_delay;
    private Gtk.Scale undo_time;
    private Gtk.ComboBoxText theme;
    private Gtk.Stack pages;
    private Gtk.Entry key_entry;
    private Gtk.Button key_save;
    private Gtk.Button key_clear;
    private Gtk.Label status;
    private LogoCredentials credentials;
    private bool key_dirty;
    private bool busy;
    private bool filling_key;
    private ulong credentials_handler;

    public PreferencesPanel (Gtk.Window parent) {
        Object (title: _("butMail Preferences"), transient_for: parent, modal: true,
            application: (Gtk.Application) GLib.Application.get_default (),
            destroy_with_parent: true, resizable: false,
            window_position: Gtk.WindowPosition.CENTER_ON_PARENT);
    }

    construct {
        credentials = LogoCredentials.get_default ();
        pages = new Gtk.Stack () { transition_type = CROSSFADE, homogeneous = true };
        var switcher = new Gtk.StackSwitcher () { stack = pages, halign = CENTER, margin_top = 12, margin_bottom = 4 };
        get_content_area ().add (switcher);
        get_content_area ().add (pages);
        var view = page ("view", _("View"));
        theme = new Gtk.ComboBoxText ();
        theme.append ("system", _("System"));
        theme.append ("light", _("Light"));
        theme.append ("dark", _("Dark"));
        theme.active_id = Application.settings.get_string ("color-scheme");
        theme.changed.connect (() => ((Application) GLib.Application.get_default ()).preview_color_scheme (theme.active_id));
        section (view, _("Appearance"));
        row (view, _("Color scheme"), theme);
        show_avatars = toggle ("show-avatars");
        remote_logos = toggle ("load-remote-avatars");
        remote_images = toggle ("always-load-remote-images");
        row (view, _("Show avatars"), show_avatars);
        row (view, _("Load avatars and company logos"), remote_logos);
        row (view, _("Always load remote images"), remote_images);
        remote_logos.sensitive = show_avatars.active;
        show_avatars.notify["active"].connect (() => remote_logos.sensitive = show_avatars.active);
        section (view, _("Logo Sources"));
        var sources_button = new Gtk.ToggleButton.with_label (_("Sources")) {
            halign = START
        };
        wide (view, sources_button);
        var sources = new Gtk.Grid () { row_spacing = 12, column_spacing = 18 };
        var sources_revealer = new Gtk.Revealer () {
            transition_type = SLIDE_DOWN,
            child = sources
        };
        sources_button.bind_property ("active", sources_revealer, "reveal-child", BindingFlags.SYNC_CREATE);
        wide (view, sources_revealer);
        section (sources, _("Logo.dev API Key"));
        key_entry = new Gtk.Entry () {
            placeholder_text = _("Enter your pk_ publishable key"), visibility = false,
            input_purpose = PASSWORD, hexpand = true, width_chars = 24,
            secondary_icon_name = "view-reveal-symbolic", secondary_icon_tooltip_text = _("Show or hide the API key")
        };
        key_entry.icon_release.connect ((position) => {
            if (position == Gtk.EntryIconPosition.SECONDARY) { key_entry.visibility = !key_entry.visibility; }
        });
        key_save = new Gtk.Button.with_label (_("Save")) { sensitive = false };
        key_save.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
        key_save.clicked.connect (() => save.begin (false));
        key_clear = new Gtk.Button.with_label (_("Clear")) { sensitive = false };
        key_clear.clicked.connect (() => {
            key_entry.text = "";
            key_dirty = true;
            save.begin (false, true);
        });
        var key_row = new Gtk.Box (HORIZONTAL, 0);
        key_row.get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
        key_row.add (key_entry);
        key_row.add (key_save);
        key_row.add (key_clear);
        wide (sources, key_row);
        hint (sources, _("Create a free <a href=\"https://logo.dev\">Logo.dev</a> account for a publishable key."), true);
        status = new Gtk.Label ("") { wrap = true, max_width_chars = 46, xalign = 0 };
        wide (sources, status);
        status.notify["label"].connect (() => {
            if (status.label != "") {
                sources_button.active = true;
            }
        });

        var reading = page ("reading", _("Reading"));
        section (reading, _("Reading and Undo"));
        read_delay = delay_scale (Application.settings.get_int ("mark-read-delay"));
        undo_time = delay_scale (Application.settings.get_int ("undo-time"));
        undo_send = toggle ("undo-send");
        undo_delete = toggle ("undo-delete");
        row (reading, _("Mark as read after"), delay_control (read_delay));
        row (reading, _("Undo time"), delay_control (undo_time));
        row (reading, _("Undo for send"), undo_send);
        row (reading, _("Undo for delete"), undo_delete);

        var system = page ("system", _("Acc/Sys"));
        section (system, _("Accounts and Signatures"));
        var accounts = new Gtk.Button.with_label (_("Account Settings…")) { action_name = Application.ACTION_PREFIX + Application.ACTION_ACCOUNT_SETTINGS };
        var signatures = new Gtk.Button.with_label (_("Edit Signatures…")) { action_name = Application.ACTION_PREFIX + Application.ACTION_MANAGE_SIGNATURES };
        wide (system, accounts);
        wide (system, signatures);
        section (system, _("System"));
        background = toggle ("run-in-background");
        row (system, _("Run in background"), background);
        hint (system, _("Start at login and notify about new mail when the window is closed."));

        add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
        add_button (_("Save"), Gtk.ResponseType.ACCEPT).get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
        set_default_response (Gtk.ResponseType.ACCEPT);
        key_entry.changed.connect (() => {
            if (!filling_key) { key_dirty = true; key_save.sensitive = credentials.ready && !busy; status.label = ""; }
        });
        credentials_handler = credentials.notify["ready"].connect (fill_key);
        credentials.refresh.begin ();
        fill_key ();
        destroy.connect (() => {
            credentials.disconnect (credentials_handler);
            ((Application) GLib.Application.get_default ()).preview_color_scheme (null);
        });
        delete_event.connect (() => busy);
        response.connect ((response_id) => {
            if (busy) { return; }
            if (response_id == Gtk.ResponseType.ACCEPT) { save.begin (true); }
            else { destroy (); }
        });
        get_content_area ().show_all ();
        get_action_area ().show_all ();
    }

    private Gtk.Grid page (string name, string title) {
        var grid = new Gtk.Grid () { margin = 20, row_spacing = 12, column_spacing = 18 };
        var scroller = new Gtk.ScrolledWindow (null, null) {
            hscrollbar_policy = NEVER, vscrollbar_policy = AUTOMATIC,
            min_content_width = 460, min_content_height = 320, max_content_height = 440,
            propagate_natural_height = true
        };
        scroller.add (grid);
        pages.add_titled (scroller, name, title);
        return grid;
    }

    private int next_row (Gtk.Grid grid) {
        int next = 0;
        foreach (var child in grid.get_children ()) {
            int top;
            grid.child_get (child, "top-attach", out top);
            next = int.max (next, top + 1);
        }
        return next;
    }

    private void wide (Gtk.Grid grid, Gtk.Widget widget) { grid.attach (widget, 0, next_row (grid), 2, 1); }

    private void row (Gtk.Grid grid, string title, Gtk.Widget control) {
        int index = next_row (grid);
        grid.attach (new Gtk.Label (title) { xalign = 0, hexpand = true }, 0, index);
        grid.attach (control, 1, index);
    }

    private void section (Gtk.Grid grid, string title) { wide (grid, new Granite.HeaderLabel (title)); }

    private void hint (Gtk.Grid grid, string title, bool markup = false) {
        var label = new Gtk.Label (title) { xalign = 0, wrap = true, max_width_chars = 46, use_markup = markup };
        label.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        label.get_style_context ().add_class (Granite.STYLE_CLASS_SMALL_LABEL);
        wide (grid, label);
    }

    private Gtk.Switch toggle (string key) {
        return new Gtk.Switch () { active = Application.settings.get_boolean (key), valign = CENTER, halign = END };
    }

    private Gtk.Scale delay_scale (int value) {
        var scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 5, 1) {
            digits = 0, round_digits = 0, draw_value = false, width_request = 120,
            hexpand = true
        };
        scale.set_value (value);
        for (int i = 0; i <= 5; i++) {
            scale.add_mark (i, Gtk.PositionType.BOTTOM, null);
        }
        return scale;
    }

    private Gtk.Widget delay_control (Gtk.Scale scale) {
        var value = new Gtk.Label (_("%d s").printf ((int) Math.round (scale.get_value ()))) {
            width_chars = 3, xalign = 1, valign = CENTER
        };
        scale.value_changed.connect (() => {
            value.label = _("%d s").printf ((int) Math.round (scale.get_value ()));
        });
        var row = new Gtk.Box (HORIZONTAL, 1);
        row.pack_start (scale, true, true);
        row.pack_end (value, false, false);
        return row;
    }

    private void fill_key () {
        key_entry.sensitive = credentials.ready;
        key_clear.sensitive = credentials.ready && !busy;
        key_entry.placeholder_text = credentials.ready
            ? _("Enter your pk_ publishable key") : _("Checking system keyring…");
        if (credentials.ready && !key_dirty) {
            filling_key = true;
            key_entry.text = credentials.key ?? "";
            filling_key = false;
        }
    }

    private async void save (bool close_after, bool clear_cache = false) {
        if (busy) {
            return;
        }
        busy = true;
        pages.sensitive = false;
        set_response_sensitive (Gtk.ResponseType.ACCEPT, false);
        set_response_sensitive (Gtk.ResponseType.CANCEL, false);
        deletable = false;
        bool succeeded = false;
        try {
            if (key_dirty) {
                yield credentials.save (key_entry.text);
                key_dirty = false;
                if (clear_cache) {
                    yield SenderAvatar.clear_cache ();
                    credentials.changed ();
                }
                status.label = credentials.key == null
                    ? (clear_cache ? _("API key and cached avatars cleared.") : _("API key removed from the system keyring."))
                    : _("API key saved in the system keyring.");
            }
            if (close_after) {
                if (background.active != Application.settings.get_boolean ("run-in-background")) {
                    yield ((Application) GLib.Application.get_default ()).set_background_enabled (background.active);
                }
                Application.settings.set_string ("color-scheme", theme.active_id ?? "system");
                Application.settings.set_boolean ("always-load-remote-images", remote_images.active);
                Application.settings.set_boolean ("load-remote-avatars", remote_logos.active);
                Application.settings.set_boolean ("show-avatars", show_avatars.active);
                Application.settings.set_int ("mark-read-delay", (int) Math.round (read_delay.get_value ()));
                Application.settings.set_int ("undo-time", (int) Math.round (undo_time.get_value ()));
                Application.settings.set_boolean ("undo-send", undo_send.active);
                Application.settings.set_boolean ("undo-delete", undo_delete.active);
            }
            succeeded = true;
        } catch (IOError.INVALID_ARGUMENT e) {
            status.label = e.message;
        } catch (Error e) {
            status.label = _("Could not save preferences: %s").printf (e.message);
        }
        busy = false;
        pages.sensitive = true;
        deletable = true;
        set_response_sensitive (Gtk.ResponseType.ACCEPT, true);
        set_response_sensitive (Gtk.ResponseType.CANCEL, true);
        key_save.sensitive = key_dirty && credentials.ready;
        key_clear.sensitive = credentials.ready;
        if (succeeded && close_after) {
            destroy ();
        }
    }
}
