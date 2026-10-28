/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    public class SenderAvatar : Gtk.Box {
        private Adw.Avatar avatar;
        private AvatarStore store;
        private string address;
        private ulong handler;
        private uint request;

        public SenderAvatar (string name, string address) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, width_request: 46, height_request: 46,
                halign: Gtk.Align.START, valign: Gtk.Align.START, hexpand: false, vexpand: false);
            add_css_class ("sender-avatar");
            this.address = address;
            avatar = new Adw.Avatar (42, name, true) {
                halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
                margin_top = 2, margin_bottom = 2, margin_start = 2, margin_end = 2
            };
            for (int color = 1; color <= 14; color++) {
                avatar.remove_css_class ("color%d".printf (color));
            }
            string identity = address.strip () != "" ? address.strip ().down () : name;
            string digest = Checksum.compute_for_string (ChecksumType.SHA256, identity);
            uint color = (uint) (uint64.parse (digest.substring (0, 8), 16) % 14) + 1;
            avatar.add_css_class ("color%u".printf (color));
            append (avatar);
            var app = (Application) GLib.Application.get_default ();
            app.settings.bind ("show-avatars", this, "visible", SettingsBindFlags.GET);
            store = app.avatars;
            handler = store.changed.connect (update);
            update ();
        }

        private void update () {
            uint current = ++request;
            avatar.custom_image = null;
            weak SenderAvatar self = this;
            store.lookup.begin (address, (obj, result) => {
                var texture = ((AvatarStore) obj).lookup.end (result);
                if (self != null && self.request == current) { self.avatar.custom_image = texture; }
            });
        }

        protected override void dispose () {
            request++;
            if (handler != 0) { store.disconnect (handler); handler = 0; }
            base.dispose ();
        }
    }
}
