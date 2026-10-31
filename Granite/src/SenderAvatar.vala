/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.SenderAvatar : Gtk.Bin {
    public int size { get; construct; }
    private Hdy.Avatar avatar;
    private AvatarStore store;
    private string? email;
    private string? image_source;
    private uint request;
    private ulong store_handler;
    private ulong visibility_handler;

    public SenderAvatar (int avatar_size) { Object (size: avatar_size); }

    construct {
        avatar = new Hdy.Avatar (size, null, true) { margin = 4 };
        avatar.get_style_context ().add_class ("butmail-avatar");
        add (avatar);
        avatar.show ();
        store = AvatarStore.get_default ();
        store_handler = store.changed.connect (reload);
        no_show_all = true;
        visible = Application.settings.get_boolean ("show-avatars");
        visibility_handler = Application.settings.changed["show-avatars"].connect (() => {
            visible = Application.settings.get_boolean ("show-avatars");
            reload ();
        });
        notify["scale-factor"].connect (reload);
        destroy.connect (() => {
            request++;
            store.disconnect (store_handler);
            Application.settings.disconnect (visibility_handler);
        });
    }

    public void bind_sender (string? name, string? address) {
        string text = name ?? address ?? _("Unknown");
        string normalized = address != null ? address.strip ().down () : "";
        if (avatar.text != text) { avatar.text = text; }
        if (email == normalized) { update_tooltip (); return; }
        email = normalized;
        reload ();
    }

    private void update_tooltip () {
        tooltip_text = image_source == null ? avatar.text : "%s\n%s".printf (avatar.text ?? "", image_source);
    }

    private void reload () {
        uint version = ++request;
        avatar.set_loadable_icon (null);
        image_source = null;
        update_tooltip ();
        if (!visible || email == null || !email.contains ("@")) { return; }
        weak SenderAvatar self = this;
        store.lookup.begin (email, int.max (48, size * get_scale_factor ()), (obj, result) => {
            var image = ((AvatarStore) obj).lookup.end (result);
            if (self == null || self.request != version || image == null) { return; }
            try {
                uint8[] png;
                var framed = ((AvatarStore) obj).frame_image (image.image, self.size);
                framed.save_to_buffer (out png, "png");
                self.avatar.set_loadable_icon (new BytesIcon (new Bytes (png)));
                self.image_source = image.source;
                self.update_tooltip ();
            } catch (Error error) { }
        });
    }

    public static async void clear_cache () throws Error {
        yield AvatarStore.get_default ().clear_cache ();
    }
}
