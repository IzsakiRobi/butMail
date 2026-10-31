/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class ButMail.BackendTrash : Object {
    public static async void empty (Camel.Folder folder, Cancellable? cancellable = null) throws Error {
        var store = folder.parent_store;
        var trash = yield BackendFolders.trash_folder (store, cancellable);
        if (trash == null || trash.full_name != folder.full_name) {
            throw new IOError.INVALID_ARGUMENT (("The selected folder is not Trash."));
        }
        if (!(folder is Camel.VTrashFolder)) {
            var info = yield store.get_folder_info (folder.full_name,
                Camel.StoreGetFolderInfoFlags.RECURSIVE | Camel.StoreGetFolderInfoFlags.NO_VIRTUAL,
                Priority.DEFAULT, cancellable);
            if (info == null || info.full_name != folder.full_name) {
                throw new IOError.NOT_FOUND (("The Trash folder could not be read."));
            }
            var descendants = new GenericArray<string> ();
            var containers = new HashTable<string, bool> (str_hash, str_equal);
            collect_descendants (store, (Camel.FolderInfo?) info.child, folder.full_name, descendants, containers);
            foreach (var path in descendants.data) {
                if (!containers.contains (path)) {
                    var child = yield store.get_folder (path, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable);
                    yield child.refresh_info (Priority.DEFAULT, cancellable);
                    yield empty_messages (child, cancellable);
                }
                if (!yield store.delete_folder (path, Priority.DEFAULT, cancellable)) {
                    throw new IOError.FAILED (("A folder in Trash could not be removed."));
                }
            }
        }
        yield empty_messages (folder, cancellable);
    }

    private static void collect_descendants (Camel.Store store, Camel.FolderInfo? info, string root, GenericArray<string> paths, HashTable<string, bool> containers) throws Error {
        while (info != null) {
            if (!info.full_name.has_prefix (root + "/") || BackendFolders.is_protected (store, info)) {
                throw new IOError.PERMISSION_DENIED (("Trash contains a protected folder and cannot be emptied."));
            }
            collect_descendants (store, (Camel.FolderInfo?) info.child, root, paths, containers);
            if ((info.flags & Camel.FolderInfoFlags.NOSELECT) != 0) {
                containers.insert (info.full_name, true);
            }
            paths.add (info.full_name);
            info = (Camel.FolderInfo?) info.next;
        }
    }

    private static async void empty_messages (Camel.Folder folder, Cancellable? cancellable) throws Error {
        var uids = folder.dup_uids ();
        folder.freeze ();
        try {
            for (uint i = 0; i < uids.length; i++) {
                var info = folder.get_message_info (uids.data[i]);
                if (info != null) {
                    info.set_flags (Camel.MessageFlags.DELETED, Camel.MessageFlags.DELETED);
                }
            }
        } finally {
            folder.thaw ();
        }

        if (!yield folder.synchronize (true, Priority.DEFAULT, cancellable)) {
            throw new IOError.FAILED (("Failed to empty Trash."));
        }
        yield folder.refresh_info (Priority.DEFAULT, cancellable);
    }
}
