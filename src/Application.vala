/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class Application : Adw.Application {
        public const string ID = "io.github.IzsakiRobi.butMail";
        public const string RESOURCE_PATH = "/io/github/IzsakiRobi/butMail";

        public Settings settings { get; private set; }
        public OnlineAccounts online_accounts { get; private set; }
        public AvatarStore avatars { get; private set; }
        public RecipientStore recipients { get; private set; }
        public bool quitting { get; private set; }
        private bool background_launch;

        public Application () {
            Object (application_id: ID, flags: ApplicationFlags.DEFAULT_FLAGS);
            add_main_option ("background", 0, OptionFlags.NONE, OptionArg.NONE, "Monitor mail without opening a window", null);
            settings = new Settings (ID);
            online_accounts = new OnlineAccounts ();
            recipients = new RecipientStore (Path.build_filename (Environment.get_user_data_dir (), ID, "recipient-history.gv"));
            avatars = new AvatarStore (settings);
            avatars.populate_recipients.begin (recipients);
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
            update_background ();
            settings.changed["run-in-background"].connect (update_background);
            var open_mail = new SimpleAction ("open-mail", new VariantType ("(ss)"));
            open_mail.activate.connect ((target) => {
                string folder, uid;
                target.get ("(ss)", out folder, out uid);
                activate ();
                foreach (var window in get_windows ()) {
                    if (window is MainWindow) { ((MainWindow) window).open_mail (folder, uid); break; }
                }
            });
            add_action (open_mail);
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
                dialog.add_link ("Company logos: Logo.dev", "https://logo.dev");
                dialog.add_link ("Free company logos: AnyLogo", "https://anylogo.dev");
                dialog.add_link ("Free company logos: CompanyEnrich", "https://companyenrich.com/free-tools/logo-api");
                dialog.add_link ("Avatars: Gravatar", "https://gravatar.com");
                dialog.present (active_window);
            });
            add_action (about);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => {
                quitting = true;
                var windows = get_windows ().copy ();
                foreach (var window in windows) {
                    window.close ();
                }
                quitting = false;
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
            preview_color_scheme (settings.get_uint ("color-scheme"));
        }

        protected override void shutdown () {
            recipients.flush ();
            base.shutdown ();
        }

        /* ----- Background Startup ----- */
        protected override int handle_local_options (VariantDict options) {
            background_launch = options.contains ("background");
            if (background_launch && !settings.get_boolean ("run-in-background")) { return 0; }
            return -1;
        }

        private void update_background () {
            string directory = Path.build_filename (Environment.get_user_config_dir (), "autostart");
            string filename = Path.build_filename (directory, ID + ".desktop");
            try {
                if (settings.get_boolean ("run-in-background")) {
                    var desktop = new KeyFile ();
                    desktop.load_from_data_dirs ("applications/" + ID + ".desktop", null, KeyFileFlags.NONE);
                    desktop.set_string ("Desktop Entry", "Exec", desktop.get_string ("Desktop Entry", "Exec") + " --background");
                    desktop.set_boolean ("Desktop Entry", "NoDisplay", true);
                    desktop.set_boolean ("Desktop Entry", "DBusActivatable", false);
                    desktop.set_boolean ("Desktop Entry", "StartupNotify", false);
                    desktop.set_boolean ("Desktop Entry", "X-GNOME-Autostart-enabled", true);
                    DirUtils.create_with_parents (directory, 0700);
                    desktop.save_to_file (filename);
                } else {
                    FileUtils.unlink (filename);
                    var windows = get_windows ().copy ();
                    foreach (var window in windows) {
                        if (window is MainWindow && !window.visible) { window.close (); }
                    }
                }
            } catch (Error error) { debug ("Unable to update background startup: %s", error.message); }
        }

        public void preview_color_scheme (uint value) {
            Adw.ColorScheme[] schemes = { Adw.ColorScheme.DEFAULT, Adw.ColorScheme.FORCE_LIGHT, Adw.ColorScheme.FORCE_DARK };
            style_manager.color_scheme = schemes[value];
        }

        protected override void activate () {
            foreach (var window in get_windows ()) {
                if (window is MainWindow) {
                    window.present ();
                    return;
                }
            }
            var main_window = new MainWindow (this);
            if (!background_launch) { main_window.present (); }
            background_launch = false;
        }
    }
}

int main (string[] args) {
    Environment.set_application_name ("butMail");
    return new ButMail.Application ().run (args);
}
