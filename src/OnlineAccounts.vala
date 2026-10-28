/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class OnlineAccount : Object {
        public string identity { get; construct; }
        public string provider { get; construct; }

        public OnlineAccount (string identity, string provider) {
            Object (identity: identity, provider: provider);
        }
    }

    public class OnlineAccounts : Object {
        public ListStore accounts { get; private set; }
        public bool ready { get; private set; }
        public string? error_message { get; private set; }
        public signal void changed ();
        private DBusObjectManagerClient? manager;

        public OnlineAccounts () {
            accounts = new ListStore (typeof (OnlineAccount));
        }

        public async void load () {
            try {
                manager = yield new DBusObjectManagerClient.for_bus (BusType.SESSION, DBusObjectManagerClientFlags.NONE,
                    "org.gnome.OnlineAccounts", "/org/gnome/OnlineAccounts", null);
                manager.object_added.connect (rebuild);
                manager.object_removed.connect (rebuild);
                manager.interface_added.connect (rebuild);
                manager.interface_removed.connect (rebuild);
                manager.interface_proxy_properties_changed.connect (rebuild);
                rebuild ();
            } catch (Error error) {
                error_message = error.message;
            }
            ready = true;
            changed ();
        }

        private void rebuild () {
            accounts.remove_all ();
            foreach (var item in manager.get_objects ()) {
                if (item.get_interface ("org.gnome.OnlineAccounts.Mail") == null) {
                    continue;
                }
                var account = item.get_interface ("org.gnome.OnlineAccounts.Account") as DBusProxy;
                if (account != null) {
                    var identity = account.get_cached_property ("PresentationIdentity");
                    var provider = account.get_cached_property ("ProviderName");
                    if (identity != null) {
                        accounts.append (new OnlineAccount (identity.get_string (), provider != null ? provider.get_string () : "Online Account"));
                    }
                }
            }
            changed ();
        }

        public static async void open_settings (Gtk.Widget parent) {
            try {
                var connection = yield Bus.get (BusType.SESSION);
                var panel = new Variant.tuple ({ new Variant.string ("online-accounts"), new Variant.array (VariantType.VARIANT, {}) });
                var parameters = new Variant.tuple ({
                    new Variant.string ("launch-panel"),
                    new Variant.array (VariantType.VARIANT, { new Variant.variant (panel) }),
                    new Variant.array (new VariantType ("{sv}"), {})
                });
                yield connection.call ("org.gnome.Settings", "/org/gnome/Settings", "org.gtk.Actions", "Activate",
                    parameters, null, DBusCallFlags.NONE, 10000);
            } catch (Error error) {
                var dialog = new Adw.AlertDialog ("Unable to Open System Settings", "Open GNOME Settings → Online Accounts manually.");
                dialog.add_response ("close", "Close");
                dialog.present (parent);
            }
        }
    }
}
