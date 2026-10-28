/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class Application : Adw.Application {
        public const string ID = "io.github.IzsakiRobi.butMail";
        public const string RESOURCE_PATH = "/io/github/IzsakiRobi/butMail";

        public Settings settings { get; private set; }
        public OnlineAccounts online_accounts { get; private set; }

        public Application () {
            Object (application_id: ID, flags: ApplicationFlags.DEFAULT_FLAGS);
            settings = new Settings (ID);
            online_accounts = new OnlineAccounts ();
        }

        protected override void startup () {
            base.startup ();
            Gtk.Window.set_default_icon_name (ID);
            Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path (RESOURCE_PATH + "/icons");
            var css = new Gtk.CssProvider ();
            css.load_from_resource (RESOURCE_PATH + "/style.css");
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            update_color_scheme ();
            settings.changed["color-scheme"].connect (update_color_scheme);
            var preferences = new SimpleAction ("preferences", null);
            preferences.activate.connect (() => { new PreferencesDialog (online_accounts).present (active_window); });
            add_action (preferences);
            online_accounts.load.begin ((obj, result) => {
                online_accounts.load.end (result);
                if (online_accounts.error_message == null && online_accounts.accounts.get_n_items () == 0 && active_window != null) {
                    var dialog = new Adw.AlertDialog ("Connect an Account", "Mail uses email accounts configured in System Settings.");
                    dialog.add_response ("accounts", "Online Accounts…");
                    dialog.close_response = "close";
                    dialog.set_response_appearance ("accounts", Adw.ResponseAppearance.SUGGESTED);
                    dialog.response.connect ((response) => {
                        if (response == "accounts") {
                            OnlineAccounts.open_settings.begin (active_window);
                        }
                    });
                    dialog.present (active_window);
                }
            });
            var about = new SimpleAction ("about", null);
            about.activate.connect (() => {
                var dialog = new Adw.AboutDialog () {
                    application_name = "butMail", application_icon = ID,
                    developer_name = "IzsakiRobi", version = "0.5",
                    license_type = Gtk.License.GPL_3_0,
                    comments = "Nothing but Mail :)",
                    website = "https://github.com/IzsakiRobi/butMail",
                    issue_url = "https://github.com/IzsakiRobi/butMail/issues"
                };
                dialog.present (active_window);
            });
            add_action (about);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => {
                var windows = get_windows ().copy ();
                foreach (var window in windows) {
                    window.close ();
                }
            });
            add_action (quit_action);
            set_accels_for_action ("win.refresh", { "F5" });
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("win.clear-selection", { "Escape" });
            set_accels_for_action ("win.compose", { "<Control>n" });
            set_accels_for_action ("win.reply", { "<Control>r" });
            set_accels_for_action ("win.reply-all", { "<Control><Shift>r" });
            set_accels_for_action ("win.forward", { "<Control><Shift>f" });
            set_accels_for_action ("app.preferences", { "<Control>comma" });
        }

        private void update_color_scheme () {
            Adw.ColorScheme[] schemes = { Adw.ColorScheme.DEFAULT, Adw.ColorScheme.FORCE_LIGHT, Adw.ColorScheme.FORCE_DARK };
            style_manager.color_scheme = schemes[settings.get_uint ("color-scheme")];
        }

        protected override void activate () {
            foreach (var window in get_windows ()) {
                if (window is MainWindow) {
                    window.present ();
                    return;
                }
            }
            new MainWindow (this).present ();
        }
    }
}

int main (string[] args) {
    Environment.set_application_name ("butMail");
    return new ButMail.Application ().run (args);
}
