/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class MessageBody : Gtk.Box {
        private static WebKit.NetworkSession? reader_session;
        private static weak WebKit.WebView? related_view;
        private Message message;
        private ulong body_handler;

        public MessageBody (Message message) {
            Object (orientation: Gtk.Orientation.VERTICAL);
            this.message = message;
            body_handler = message.notify["body"].connect (render);
            render ();
        }

        private void render () {
            while (get_first_child () != null) { remove (get_first_child ()); }
            if (!message.is_html) {
                var label = new Gtk.Label (message.body) {
                    xalign = 0, wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR, selectable = true
                };
                label.add_css_class ("message-body");
                append (label);
                return;
            }
            var manager = new WebKit.UserContentManager ();
            manager.register_script_message_handler ("height", "butmail-reader");
            if (reader_session == null) {
                reader_session = new WebKit.NetworkSession (
                    Path.build_filename (Environment.get_user_data_dir (), Application.ID, "reader"),
                    Path.build_filename (Environment.get_user_cache_dir (), Application.ID, "reader"));
                reader_session.get_cookie_manager ().set_accept_policy (WebKit.CookieAcceptPolicy.NEVER);
            }
            var view = related_view != null
                ? (WebKit.WebView) Object.new (typeof (WebKit.WebView), "related-view", related_view, "user-content-manager", manager)
                : (WebKit.WebView) Object.new (typeof (WebKit.WebView), "network-session", reader_session, "user-content-manager", manager);
            related_view = view;
            view.height_request = 160;
            weak WebKit.WebView weak_view = view;
            var web_settings = view.get_settings ();
            web_settings.enable_javascript_markup = false;
            web_settings.enable_page_cache = false;
            web_settings.enable_html5_database = false;
            web_settings.enable_html5_local_storage = false;
            web_settings.enable_media = false;
            web_settings.enable_media_stream = false;
            web_settings.enable_fullscreen = false;
            manager.script_message_received["height"].connect ((value) => {
                int height = (int) value.to_double ();
                if (weak_view != null) { weak_view.height_request = int.max (64, int.min (20000, height)); }
            });
            manager.add_script (new WebKit.UserScript.for_world (
                "new ResizeObserver(() => { window.webkit.messageHandlers.height.postMessage(Math.ceil(document.body.getBoundingClientRect().height) + 40); }).observe(document.body);",
                WebKit.UserContentInjectedFrames.TOP_FRAME, WebKit.UserScriptInjectionTime.END,
                "butmail-reader", null, null));
            view.decide_policy.connect ((decision, type) => {
                if (type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) { decision.ignore (); return true; }
                if (type != WebKit.PolicyDecisionType.NAVIGATION_ACTION) { return false; }
                var navigation = ((WebKit.NavigationPolicyDecision) decision).navigation_action;
                string uri = navigation.get_request ().get_uri ();
                if (navigation.get_navigation_type () == WebKit.NavigationType.LINK_CLICKED &&
                    (uri.has_prefix ("https://") || uri.has_prefix ("http://") || uri.has_prefix ("mailto:"))) {
                    new Gtk.UriLauncher (uri).launch.begin (get_root () as Gtk.Window, null);
                }
                if (uri != "about:blank") { decision.ignore (); return true; }
                return false;
            });
            view.context_menu.connect (() => { return true; });
            bool remote_images = ((Application) GLib.Application.get_default ()).settings.get_boolean ("always-load-remote-images");
            string image_sources = remote_images ? "data: https: http:" : "data:";
            string policy = "default-src 'none'; img-src " + image_sources + "; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'";
            view.load_html ("<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' content=\"" + policy +
                "\"><style>html{overflow:hidden}body{margin:20px 24px;font:14px sans-serif;overflow-wrap:anywhere}img{max-width:100%;height:auto}</style></head><body>" +
                message.body + "</body></html>", "about:blank");
            append (view);
        }

        protected override void dispose () {
            if (body_handler != 0) { message.disconnect (body_handler); body_handler = 0; }
            base.dispose ();
        }
    }
}
