/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Mail.TrashOperations : Object {
    public static string? physical_path (Camel.Store store) {
        var settings = store.ref_settings ();
        var settings_class = (ObjectClass) settings.get_type ().class_ref ();
        if (settings_class.find_property ("real-trash-path") == null) { return null; }
        string? path;
        settings.get ("real-trash-path", out path);
        return path != null && path != "" ? path : null;
    }

    public static async Camel.Folder? get_folder (Camel.Store store, Cancellable? cancellable = null) throws Error {
        var path = physical_path (store);
        if (path != null) {
            return yield store.get_folder (path, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable);
        }
        return yield store.get_trash_folder (Priority.DEFAULT, cancellable);
    }

    public static bool is_trash (Camel.Folder folder) {
        var path = physical_path (folder.parent_store);
        return path != null ? !(folder is Camel.VTrashFolder) && folder.full_name == path
            : Camel.FolderFlags.IS_TRASH in (Camel.FolderFlags) folder.get_flags ();
    }

    public static bool hidden_virtual (Camel.Store store, Camel.FolderInfo info) {
        return physical_path (store) != null && (info.flags & Camel.FolderInfoFlags.VIRTUAL) != 0
            && (info.flags & Camel.FOLDER_TYPE_MASK) == Camel.FolderInfoFlags.TYPE_TRASH;
    }

    public static async void empty (Camel.Folder folder, Cancellable? cancellable = null) throws Error {
        var store = folder.parent_store;
        var trash = yield get_folder (store, cancellable);
        if (trash == null || trash.full_name != folder.full_name) {
            throw new IOError.INVALID_ARGUMENT (_("The selected folder is not Trash."));
        }
        if (!(folder is Camel.VTrashFolder)) {
            var info = yield store.get_folder_info (folder.full_name,
                Camel.StoreGetFolderInfoFlags.RECURSIVE | Camel.StoreGetFolderInfoFlags.NO_VIRTUAL,
                Priority.DEFAULT, cancellable);
            if (info == null || info.full_name != folder.full_name) {
                throw new IOError.NOT_FOUND (_("The Trash folder could not be read."));
            }
            var descendants = new Gee.ArrayList<string> ();
            var containers = new Gee.HashSet<string> ();
            collect_descendants (store, (Camel.FolderInfo?) info.child, folder.full_name, descendants, containers);
            foreach (var path in descendants) {
                if (!containers.contains (path)) {
                    var child = yield store.get_folder (path, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable);
                    yield child.refresh_info (Priority.DEFAULT, cancellable);
                    yield empty_messages (child, cancellable);
                }
                if (!yield store.delete_folder (path, Priority.DEFAULT, cancellable)) {
                    throw new IOError.FAILED (_("A folder in Trash could not be removed."));
                }
            }
        }
        yield empty_messages (folder, cancellable);
    }

    private static void collect_descendants (Camel.Store store, Camel.FolderInfo? info, string root, Gee.List<string> paths, Gee.Set<string> containers) throws Error {
        while (info != null) {
            if (!info.full_name.has_prefix (root + "/") || FolderOperations.is_protected (store, info)) {
                throw new IOError.PERMISSION_DENIED (_("Trash contains a protected folder and cannot be emptied."));
            }
            collect_descendants (store, (Camel.FolderInfo?) info.child, root, paths, containers);
            if ((info.flags & Camel.FolderInfoFlags.NOSELECT) != 0) {
                containers.add (info.full_name);
            }
            paths.add (info.full_name);
            info = (Camel.FolderInfo?) info.next;
        }
    }

    private static async void empty_messages (Camel.Folder folder, Cancellable? cancellable) throws Error {
        unowned var uids = folder.get_uids ();
        folder.freeze ();
        try {
            for (uint i = 0; i < uids.length; i++) {
                var info = folder.get_message_info (uids[i]);
                if (info != null) {
                    info.set_flags (Camel.MessageFlags.DELETED, Camel.MessageFlags.DELETED);
                }
            }
        } finally {
            folder.thaw ();
            folder.free_uids (uids);
        }

        if (!yield folder.synchronize (true, Priority.DEFAULT, cancellable)) {
            throw new IOError.FAILED (_("Failed to empty Trash."));
        }
        yield folder.refresh_info (Priority.DEFAULT, cancellable);
    }
}
