// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2017 elementary LLC. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

namespace ButMail {
    public class MailSession : Camel.Session {
        public E.SourceRegistry registry { get; private set; }
        private E.CredentialsPrompter credentials_prompter;

        public MailSession () {
            Object (
                user_data_dir: Path.build_filename (Environment.get_user_data_dir (), Application.ID, "mail"),
                user_cache_dir: Path.build_filename (Environment.get_user_cache_dir (), Application.ID, "mail")
            );
            Camel.init (Path.build_filename (Environment.get_user_data_dir (), Application.ID), false);
            set_network_monitor (E.NetworkMonitor.get_default ());
            set_online (true);
        }

        public async void start (Cancellable cancellable) throws Error {
            registry = yield new E.SourceRegistry (cancellable);
            credentials_prompter = new E.CredentialsPrompter (registry);
            credentials_prompter.set_auto_prompt (false);
            credentials_prompter.get_dialog_parent.connect (() => {
                return ((Gtk.Application) GLib.Application.get_default ()).active_window;
            });
        }

        /* ----- Session Services ----- */
        public override unowned Camel.FilterDriver get_filter_driver (string type, Camel.Folder? folder) throws Error {
            var driver = new Camel.FilterDriver (this);
            return (Camel.FilterDriver) driver.ref ();
        }

        /* ----- EDS Authentication ----- */
        public override bool authenticate_sync (Camel.Service service, string? mechanism, GLib.Cancellable? cancellable = null) throws GLib.Error {

            Camel.ServiceAuthType? authtype = null;
            bool try_empty_password = false;
            var result = Camel.AuthenticationResult.REJECTED;

            if (mechanism == "none") {
                mechanism = null;
            }

            if (mechanism != null) {

                authtype = Camel.Sasl.authtype (mechanism);

                if (authtype != null && !authtype.need_password) {
                    result = service.authenticate_sync (mechanism, cancellable);

                    if (result == Camel.AuthenticationResult.REJECTED) {
                        throw new Camel.ServiceError.CANT_AUTHENTICATE (
                            "%s authentication failed",
                            mechanism
                        );
                    }

                    return (result == Camel.AuthenticationResult.ACCEPTED);
                }

                var sasl = Camel.Sasl.for_service (((Camel.Provider)service.provider).protocol, mechanism, service);
                if (sasl != null) {
                    try_empty_password = sasl.try_empty_password_sync (cancellable);
                }
            }

            var source = registry.ref_source (service.get_uid ());
            if (source == null) { throw new IOError.NOT_FOUND ("Mail account is no longer available."); }

            result = Camel.AuthenticationResult.REJECTED;

            if (try_empty_password) {
                result = service.authenticate_sync (mechanism, cancellable);
            }

            if (result == Camel.AuthenticationResult.REJECTED) {

                return credentials_prompter.loop_prompt_sync (source, E.CredentialsPrompterPromptFlags.ALLOW_SOURCE_SAVE, (prompter, source, credentials, out out_authenticated, cancellable) => try_credentials_sync (prompter, source, credentials, out out_authenticated, cancellable, service, mechanism), cancellable);
            } else {
                return (result == Camel.AuthenticationResult.ACCEPTED);
            }
        }

        public override bool get_oauth2_access_token_sync (Camel.Service service, out string? access_token, out int expires_in, Cancellable? cancellable = null) throws GLib.Error {
            GLib.Error? local_error = null;

            var source = registry.ref_source (service.get_uid ());
            if (source == null) {
                throw new GLib.IOError.NOT_FOUND ("Corresponding source for service with UID “%s” not found", service.get_uid ());
            }

            var cred_source = registry.find_extension (source, E.SOURCE_EXTENSION_COLLECTION);
            if (cred_source == null || !E.util_can_use_collection_as_credential_source (cred_source, source)) {
                cred_source = source;
            }

            bool success = false;

            try {
                success = cred_source.get_oauth2_access_token_sync (cancellable, out access_token, out expires_in);
            } catch (Error e) {
                local_error = e;

                if (e is GLib.IOError.CONNECTION_REFUSED || e is GLib.IOError.NOT_FOUND) {
                    local_error = new Camel.ServiceError.CANT_AUTHENTICATE (e.message);

                    try {
                        if (cred_source.invoke_credentials_required_sync (E.SourceCredentialsReason.REJECTED, "", 0, e)) {
                            local_error = null;
                        }
                    } catch (Error invoke_error) {
                        local_error = invoke_error;
                    }
                }
            }

            if (local_error != null) {
                throw local_error;
            }

            return success;
        }

        public bool try_credentials_sync (E.CredentialsPrompter prompter, E.Source source, E.NamedParameters credentials, out bool out_authenticated, GLib.Cancellable? cancellable, Camel.Service service, string? mechanism) throws GLib.Error {
            string credential_name = null;

            if (source.has_extension (E.SOURCE_EXTENSION_AUTHENTICATION)) {
                unowned var auth_extension = (E.SourceAuthentication) source.get_extension (E.SOURCE_EXTENSION_AUTHENTICATION);

                credential_name = auth_extension.dup_credential_name ();

                if (credential_name != null && credential_name.length == 0) {
                    credential_name = null;
                }
            }

            service.set_password (credentials.get (credential_name ?? E.SOURCE_CREDENTIAL_PASSWORD));

            Camel.AuthenticationResult result = service.authenticate_sync (mechanism, cancellable);

            out_authenticated = (result == Camel.AuthenticationResult.ACCEPTED);

            if (out_authenticated) {
                var credentials_source = prompter.get_provider ().ref_credentials_source (source);

                if (credentials_source != null) {
                    credentials_source.invoke_authenticate_sync (credentials, cancellable);
                }
            }

            return result == Camel.AuthenticationResult.REJECTED;
        }
    }
}
