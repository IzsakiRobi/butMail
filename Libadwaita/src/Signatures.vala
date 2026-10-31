/* SPDX-License-Identifier: GPL-3.0-or-later */
namespace ButMail {
    public class Signatures : Object {
        public static string get_html (Settings settings, string account) {
            string key = account.strip ().down ();
            var value = settings.get_value ("account-signatures").lookup_value (key, VariantType.STRING);
            return value != null ? value.get_string () : settings.get_string ("signature-html");
        }

        public static void set_html (Settings settings, string account, string html) {
            string key = account.strip ().down ();
            var builder = new VariantBuilder (new VariantType ("a{ss}"));
            var entries = settings.get_value ("account-signatures").iterator ();
            string address, saved;
            while (entries.next ("{ss}", out address, out saved)) {
                if (address != key) { builder.add ("{ss}", address, saved); }
            }
            builder.add ("{ss}", key, html);
            settings.set_value ("account-signatures", builder.end ());
        }
    }
}
