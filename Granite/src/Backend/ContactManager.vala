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

public class Mail.ContactManager : GLib.Object {
    private static ContactManager? instance;
    private Folks.IndividualAggregator individual_aggregator;
    private Gee.HashSet<Folks.Individual> observed = new Gee.HashSet<Folks.Individual> ();
    private uint avatar_update_id;
    public signal void avatars_changed ();

    public static unowned ContactManager get_default () {
        if (instance == null) { instance = new ContactManager (); }
        return instance;
    }

    construct {
        individual_aggregator = Folks.IndividualAggregator.dup ();
        load_contacts.begin ();
    }

    private async void load_contacts () {
        individual_aggregator.individuals_changed_detailed.connect (() => {
            observe_contacts ();
            queue_update ();
        });
        observe_contacts ();
        try {
            yield individual_aggregator.prepare ();
            observe_contacts ();
            queue_update ();
        } catch (Error error) {
            warning ("Unable to load contacts: %s", error.message);
        }
    }

    private void observe_contacts () {
        foreach (var individual in individual_aggregator.individuals.values) {
            if (!observed.add (individual)) { continue; }
            individual.notify["avatar"].connect (queue_update);
            individual.notify["email-addresses"].connect (queue_update);
            individual.notify["display-name"].connect (queue_update);
        }
    }

    private void queue_update () {
        if (avatar_update_id != 0) { return; }
        avatar_update_id = Timeout.add (100, () => {
            avatar_update_id = 0;
            var contacts = new GenericArray<Recipient> ();
            foreach (var individual in individual_aggregator.individuals.values) {
                foreach (var field in individual.email_addresses) {
                    string email = field.value.strip ();
                    if (email != "") {
                        contacts.add (new Recipient (individual.display_name, email, 1000, 0));
                    }
                }
            }
            RecipientStore.get_default ().replace_contacts (contacts);
            avatars_changed ();
            return Source.REMOVE;
        });
    }

    public async LoadableIcon? lookup_avatar (string email) {
        foreach (var individual in individual_aggregator.individuals.values) {
            if (individual.avatar == null) { continue; }
            foreach (var field in individual.email_addresses) {
                if (field.value.strip ().casefold () == email.casefold ()) { return individual.avatar; }
            }
        }
        return null;
    }
}
