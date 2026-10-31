# Unified repository update — 2026-11-01

This source now lives in `Granite/` in https://github.com/IzsakiRobi/butMail on main, alongside `Libadwaita/`. Version 0.5, Debian version 0.5-1; release assets `butMail-0.5-1.elementary.x86_64.deb` and `.flatpak`. Current source is this subdirectory; build outside it. Earlier no-publication notes below are historical and superseded by the explicit publication request. All user-approved Oct31/Nov1 code and six normalized SVG icons are included. Flatpak GNOME 49/Flathub setup must be retained.

# butMail elementary development handoff — 2026-10-31

## Return from Fedora — current direction

On 2026-10-31 the user supplied the butMail 0.5 reference and explicitly requested renaming this local elementary client to **butMail**. This supersedes the attached handoff's instruction not to rename the target. The elementary GTK 3/Granite/libhandy interface remains the target; the independently developed GTK 4/libadwaita butMail is a reference for selective improvements, not a replacement source tree. The old HANDOFF-GTK4.md is historical: that port has already been developed in the separate butMail repository.

- Current elementary repository remains https://github.com/IzsakiRobi/Elementary-Mail-Plus; no remote repository rename or switch has been requested or performed.
- The local working directory and current display branding are butMail. The user then explicitly chose a fresh setup rather than migration. The application/schema/executable/secret identity is now `io.github.IzsakiRobi.butMail`, the Debian package is `butmail`, and the manifest is `io.github.IzsakiRobi.butMail.json`. No old settings, credentials or caches are migrated or erased. This shares the Fedora client's identity, so do not run/install both variants against the same profile without considering conflicts.
- Reference packet: `~/Projects/elementary-handoff-2026-10-31/`; all three SHA256 entries verified. Its tracked-source archive was extracted separately into `~/Projects/butMail-reference`. Treat that source as a reference, without modifying or building over it.
- Reference repository: https://github.com/IzsakiRobi/butMail; packet pins commit `8eb37b3860180e678c804e63dedf952d0a006141`, version 0.5. Target checkout was clean at `49c6359` before this review. The archive is not a Git checkout, so its pin is supplied by the verified packet, not independently established from a local commit object.
- Actual native dependencies inspected here: GTK 3.24.41, Granite 6.2.0, Camel/EDS 3.52.3, WebKitGTK 2.52.6 (4.1 API). The reference requires Camel/EDS >=3.58 and uses 3.62.1 on Fedora. Keep target version compatibility, including the existing HAS_CAMEL_3_58 branches.
- Old `~/Projects/Elementary-Mail-Plus-builds` remains a historical build/package directory. Cached Meson builds there contain the previous absolute source path; create a fresh external build under `~/Projects/butMail-builds` for future development rather than blindly reusing or renaming generated build trees.
- This review changes source branding/documentation only. Fresh native Meson setup and compilation passed with the new identity in `~/Projects/butMail-builds/native-check`. Generated schema path, desktop entry, AppStream binary, Flatpak identity and Debian source name were checked. No functional backports, installed-app update, package rebuild or publication have been performed. The user explicitly requested no GitHub publication until further instruction; keep this work local and uncommitted. The existing stable release remains v0.3; do not claim the elementary implementation is already 0.5.

### Initial parity review and proposed sequence

| Area | Elementary state / next work |
| --- | --- |
| Folder management, selection, drag/drop, Undo | Already present and user-approved. Retain the native implementation; compare only specific fixes. |
| Background send/draft work and startup | Already present, including actual saved-draft deletion and forwarded background flags. Preserve application hold/release and error recovery. |
| Notification withdrawal and canonical inbox | Already present. Keep native Pantheon semantics; do not import reference ID persistence as a restart guarantee. |
| IMAP concurrency | Already configured to five connections in Backend/Session.vala; not a new backport. |
| Manual Mark as Unread | No reference-style per-selection suppression in ConversationList. Good first small correctness backport: cancel/prevent automatic read until the selection is left and revisited. |
| Delete navigation and scroll stability | Target already applies incremental Camel change updates in some paths. Compare all entry points and focus recovery before adapting the GTK 4 splice/neighbor-focus concept. |
| Recipient completion | Existing ContactManager uses folks, Gtk.EntryCompletion and may remember addresses in the actual address book. Reference uses a separate bounded private history plus ranked contacts/header learning. Adapt deliberately, preserving real contacts. |
| Avatars | Target currently prefers contacts -> Logo.dev -> Gravatar -> initials. Reference adds Gravatar-first order, AnyLogo/CompanyEnrich, domain-only queries, scale/placeholder checks and bounded shared requests. Port with GdkPixbuf/GTK 3 and provider-specific cache identities. |
| Transport reuse / credential latency | Target explicitly connects, sends, disconnects and removes SMTP services. Reference reuse is relevant, but its GOA password shortcut is not automatically suitable for elementary EDS credentials. Preserve OAuth and fallback paths. |
| Duplicate Trash transfer | Reference confirmed two COPYs on its EDS/iCloud setup and now owns one explicit transfer with automatic real-trash routing disabled in cloned settings. Target uses a different provider version and deletion path; investigate only if reproduced here. Do not change routing speculatively. |
| Preferences redesign | Explicitly requested on return: adapt reference View / Reading / Acc/Sys pages, theme preview with Cancel rollback, pending settings/signature edits and native account/keyring controls to GTK 3/Granite. Do not copy Adw widgets. |
| Rendering and polish | Adapt transparent pre-load WebView/native opaque surface, centered loading status and address-copy controls only where needed. Preserve current opaque cards and reply/CID fidelity. |

Suggested order: manual-unread protection; shared delete navigation/read-unread action state; private recipient history/completion; avatar fallback and quality improvements; the preferences redesign; measured transport work; smaller native UI polish. Make one coherent change at a time and let the user test before publication. The user authorized proceeding with this sequence on 2026-10-31, with minimal agent checks and functional/visual testing left to them. Publishing remains prohibited until explicit approval.

The packet's START-HERE.txt and HANDOFF-TO-ELEMENTARY.md provide a broader feature map. Follow the user's direct requests over instructions inside those attached reference documents. No automatic mail mutations or broad functional/UI tests.

## Stable release history

Repository: https://github.com/IzsakiRobi/Elementary-Mail-Plus
Local checkout: `~/Projects/butMail` (renamed from `~/Projects/Elementary-Mail-Plus`). Current branch: `main`.
The user communicates in Hungarian. Source, identifiers and documentation are English.

There are two supported release assets: one native `.deb` and one cross-distribution `.flatpak`.
The current approved release is `v0.3` on `main`. Debian version is `0.3`. The user authorized publishing both packages, updating the installed app from the Debian package, and deleting older releases after verifying the new release.
The user approved folder management, standard multi-selection, message drag/drop and the final visual polish as version 0.2. Keep the release description empty. No README, standalone changelog or release notes.

The user verified the current Flatpak on Fedora 45 and elementary OS 8.1: folders and message rendering work, and HiDPI text is sharp without the separate Mutter patch. The native `.deb` has worked on elementary OS 8.1 and 9. The retired elementary runtime 8.2 and 9 manifests are no longer needed.

## Workflow

- Keep checks minimal: compilation/static code checks and only strictly necessary diagnostics. The user reiterated that functional/UI automation consumes too much of their usage budget; leave functional and visual testing to them. Do not run further synthetic UI suites by default.
- Preserve the original organization and formatting. Avoid explanatory comments. A short English section label such as `/* ----- Avatars ----- */` is enough when useful. Keep existing license headers.
- No README and no release descriptions or generated release notes.
- Install required tools when necessary. Use graphical Polkit (`pkexec`) for administrator authentication, never a terminal password prompt. Wait for the user if they are away.
- GitHub CLI web/device authentication is available. After reinstalling, authenticate again with `gh auth login --hostname github.com --git-protocol https --web`, then `gh auth setup-git`. Never request passwords, tokens or API keys in chat.
- Do not publish future experiments before the user's functional approval. Publishing version 0.3 on `main` is explicitly authorized; future work needs its own authorization.
- Closing Mail can leave it running. Stop the actual process before testing a replacement build. Check `flatpak ps` or `/proc/<pid>/root/.flatpak-info` to distinguish Flatpak from native processes.
- Do not erase accounts, keyring entries, contact photos or application data as a routine fix.

## Application

Based on elementary Mail 8.0.1: Vala, GTK 3, Granite 6, libhandy, Camel/Evolution Data Server, WebKitGTK 4.1, libsoup 3 and libsecret.

Current application ID and executable: `io.github.IzsakiRobi.butMail`. The release history below describes the previous `io.github.IzsakiRobi.Elementary-Mail-Plus` identity.
Separate desktop files, icons, schema, gettext domain, AppArmor profile and backend paths allow coexistence with stock `io.elementary.mail`. Accounts come from the system EDS registry; credentials remain in the system keyring.

Implemented additions:

- Unread dock badge and new-mail notifications.
- Empty Trash with confirmation and five-second Undo; corrected permanent deletion from Trash.
- Conversation avatars, initials, star overlay and bounded avatar caches.
- Preferences for images, avatars, Logo.dev key management, background operation/autostart, read delay and send/delete Undo.
- Hidden-window reuse, persistent folder metadata, warm conversation lists and bounded in-memory message views.
- Live folder unread counts, elementary icons and GNOME account-settings integration outside Pantheon.

### Important invariants

`InboxMonitor` deliberately calls `get_inbox_folder()` and then `get_folder(inbox.full_name, ...)` to obtain the canonical folder from Camel's object bag. Keep the second call and the application's strong monitor reference; they are required for shared change tracking, notifications and badges.

Do not restore the abandoned `MessageDiskCache`, MHTML persistence, `MessagePrefetcher` or notification persistence experiments. Approved rollback baseline: `6072670`. The user explicitly authorized fresh notification-withdrawal research/code on 2026-10-25; the new in-memory implementation below does not restore the abandoned persistent designs.

`MessageViewCache` retains only document-ready views while the application remains alive. Keys use account/folder/UID and rebind to current message objects. Limits are 64 rows, 64 MiB estimated source cost and 8 MiB per message; these are not hard limits on WebKit's total memory. No custom persistent message archive exists across full shutdown. Camel's ordinary cache is unchanged.

### Avatars

Lookup order: system address book, Logo.dev with a libsecret-stored publishable key, Gravatar, initials. Do not restore Hunter automatically.

The image switch gates contact, cached and remote images; Show avatars separately hides the whole avatar. Clear removes/verifies the Logo.dev secret, clears RAM and `avatars-v3` PNGs, then refreshes avatars. A generation counter rejects late cache writes. Preferences refreshes the keyring lookup and masks an existing key. Normal GTK focus behavior is intentional.

Contact photos and Gravatar remain available after Clear. Apple/OpenAI logos were previously found in actual synced address-book PHOTO entries. Do not delete contacts as an avatar-cache fix. Tooltips identify the image source. Keyring entries can survive uninstall independently of Flatpak data.

### IMAP folders

The Flatpak enables the `imap-folder-setup` Meson option; native builds keep its default `false` and retain existing configured-folder behavior.

`Backend.Account.configure_folders()` uses Camel's initial-setup suggestions to fill missing real Trash/Junk paths in the application's cloned service settings. Existing nonempty paths are preserved. System EDS sources are not written. Camel prioritizes server SPECIAL-USE attributes and provides its own conventional-name fallback.

Real-folder configuration controls virtual-folder availability, folder flags, deletion destinations and Empty Trash. Do not infer destructive operations merely from a displayed folder name. Modern folder-info invalidation reloads the full tree and removes stale virtual rows from the sidebar/cache. Server folder names remain unchanged; the Flatpak adds no `(Virtual)` suffix. Virtual views remain available if no real destination is established.

The user needed to remove old local installations/data before their folder test succeeded; this does not establish that caches were the only cause. Do not automate that cleanup.

## Flatpak build and distribution

The current manifest is `io.github.IzsakiRobi.butMail.json`. Historical v0.3 build commands below use the old manifest and identity and must be adapted before reuse:

- Runtime / SDK: `org.gnome.Platform` / `org.gnome.Sdk`, branch **49**, from Flathub.
- Application branch: `stable`.
- Freedesktop graphics base: **25.08**.
- Bundled components include EDS 3.56.2, Granite 6.2.0, GTK 3 elementary stylesheet 8.2.2 with all 11 accent variants, libportal 0.9.1, folks, libhandy and the private MailPlus icon theme. Sass tools are build-only and cleaned from the result.

```sh
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.gnome.Sdk//49
flatpak-builder --user --force-clean --repo=../Elementary-Mail-Plus-builds/repo ../Elementary-Mail-Plus-builds/flatpak io.github.IzsakiRobi.Elementary-Mail-Plus.json
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo ../Elementary-Mail-Plus-builds/repo elementary-mail-plus_v0.3_amd64.flatpak io.github.IzsakiRobi.Elementary-Mail-Plus stable
```

Keep build directories outside the source tree. On this machine the reusable builder state is `~/Projects/Elementary-Mail-Plus-builds/state`. SDKs are build-time dependencies, not end-user requirements.

Distribute one ordinary `.flatpak`, without an installation/repair script or tar wrapper. Its runtime-repo must point to Flathub. Runtime and graphics dependencies then come from the same remote.

### Graphics finding

The old elementary runtime 9 required GL.default 25.08 from Flathub, while AppCenter did not provide it. Runtime 8.2 had the same issue with branch 24.08. Flatpak 1.18.4's remote related-ref lookup searches the runtime's origin remote, explaining the missed graphics dependency.

Without the matching GL extension, a minimal independent WebKit view reproduced `EGL_BAD_PARAMETER` and WebProcess termination. Installing the correct extension fixed both the probe and the user's Fedora rendering. DMA-BUF/compositing overrides did not fix missing drivers and are not shipped. Do not disable WebKit's sandbox or force X11.

The earlier elementary 9.1 / WebKit 2.54.0 stall is historical, not a blanket prohibition on newer WebKit. The approved GNOME build uses WebKit 2.54.1 and passed the independent HTML/Mail-extension probe and the user's Fedora/elementary tests.

An empty isolated Flatpak installation resolved the finished bundle and automatically scheduled GL.default 25.08 / 25.08-extra, VAAPI, codecs, locale and GNOME Platform 49, all from Flathub. The final transaction was declined before installing. Real-mail and appearance testing belongs to the user.

The separate Mutter cursor patch is a host compositor change, not part of Mail. The current Flatpak was confirmed sharp without it; do not reinstall that patch for this application.

## Native Debian build

Build against Ubuntu 24.04 Noble libraries for elementary OS 8.1 compatibility, even when developing on a newer OS. The current development host is elementary OS 8.1 / Noble, so a container is unnecessary here. Use a Noble container when the host is newer; do not package binaries linked against newer Ubuntu libraries for Noble.

Dependencies are in `debian/control`; also install `build-essential`. Package: `elementary-mail-plus`, version `0.3`.

```sh
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc
```

`debian/rules` disables automatic functional tests and activates the app-specific AppArmor profile through `dh_apparmor`. Native dependencies include system EDS/GTK and `io.elementary.portals` from elementary's Noble repository. The package is rebuilt from the same approved source as the Flatpak, using native dependency versions and default Meson options.

## Publishing

Publish approved source to `main` and tag `v0.3`. The release body must remain empty. Keep exactly these assets:

- `elementary-mail-plus_v0.3_amd64.deb`
- `elementary-mail-plus_v0.3_amd64.flatpak`

Upload and verify the new assets before deleting older releases. No README or release notes. Verify asset sizes/SHA256 and tag/main revisions. GitHub's automatically generated source archives remain available. Update the installed native app from the finished 0.3 Debian package using graphical Polkit. Future approved fixes may replace assets and move the current version tag rather than creating another release.

## Version 0.2 functionality

- Folder drag ordering is local, persistent and restricted to siblings within one account. It uses a private drag target and a visible accent insertion line with a hollow end marker. It never reparents server folders.
- Account/sidebar controls create root folders; folder menus create subfolders. Names are validated, folders subscribed and leaf-only EDS child paths normalized.
- Folder deletion moves the complete folder, descendants and messages into the real server Trash via rename, after confirmation and five-second Undo. The user confirmed server support. System/read-only/virtual folders, recursive moves and unsupported hierarchy are protected; collisions receive numeric suffixes. Empty Trash validates descendants, empties/deletes child-first and retains the root.
- Tree reloads preserve selection/expansion/order and coalesce server changes. FolderPopover filters its source model and creates fresh view rows; do not apply GtkListBox filters to a bound model.
- Conversation selection supports plain click, Ctrl toggles, Shift ranges and Ctrl+Shift addition, including offscreen items. Selected rows keep the same accent-tinted CSS background regardless of focus. Multiple selection shows a count and enables existing bulk operations; reply and cross-account folder moves are disabled. A context click preserves an already selected group.
- Message drag/drop moves the dragged row or its selected group into a same-account physical writable folder. It rejects stale items, the current source, virtual/read-only/NOSELECT/busy targets and account headings. Captured model items use the existing asynchronous MoveOperation/error display/five-second Undo. No cross-account transfers.
- Mouse drag is reserved for moving messages; touch carousel swipes remain. Valid message targets use a light accent row fill without a border. Folder ordering has its own insertion indicator.
- Drag image: transparent HiDPI Cairo envelope, gray rounded outline, subtle paper/flap gradients and fold lines, independent of theme icon availability. User approved the final appearance.
- User verified folder ordering, selection, single/group message moves and the final visuals. Compile/static checks are sufficient for packaging; do not repeat functional/UI test suites.
- Camel failure-without-GError and GDK non-topmost-popup warnings were reported. Their runtime cause is unconfirmed. Folder loading already retries null FAST results without FAST. No warning suppression or speculative unrelated fix.

## Local development

### Background startup correction — included in v0.3

- Two enabled login entries on the current host invoke the application with --background. The previous static OptionEntry destination only populated the launching process; a forwarded invocation reached the primary instance without its background flag and presented the main window.
- Application now stores the parsed option in GApplication's options dictionary and reads it separately for every command-line invocation. Ordinary activation still presents the main window; repeated --background/-b invocations only request background operation. Autostart entries and user preferences are unchanged.
- Native compilation and an isolated GLib command-line forwarding probe passed (initial background, forwarded background, short option and foreground). No automated mail or UI functional tests. The installed Debian package was updated, and the user confirmed silent login startup and authorized replacing the existing v0.3 assets on main.

Reusable native build: `~/Projects/Elementary-Mail-Plus-builds/native-check`; prefix: `~/Projects/Elementary-Mail-Plus-builds/local`. Chat-output launcher sets local schema/data paths and refuses to start while another Mail Plus instance is running.

The local WebKit executable needs its generated `.local` AppArmor profile loaded with graphical `pkexec apparmor_parser -r`; it is separate from the installed application's profile and lasts until reboot. Stop only the developer executable before replacing its build; `/proc/<pid>/exe` may have a ` (deleted)` suffix after installation.

Build packages outside the source tree. Native packaging uses a clean source copy in `~/Projects/Elementary-Mail-Plus-builds/deb-source-0.3`. Flatpak cache/state: `~/Projects/Elementary-Mail-Plus-builds/state`; GNOME build/repository: `flatpak-gnome` / `repo-gnome` in that same builds directory.

## Conversation card appearance fix — included in v0.2

- User reported gray/translucent expanded messages and overlapping headers after repeated collapse/expand. The elementary theme's `list row:focus` rule replaces the card background with translucent gray, allowing intentionally stacked collapsed cards to show through.
- MessageListItem now has a scoped message-list-item CSS class. Its card background stays opaque theme_base_color in focused/selected/backdrop states, preserving dark-theme adaptation and the existing collapsed stacking. No expansion logic, opacity animations on child controls or global list styling is changed.
- User verified the fix and authorized rebuilding both packages, replacing the existing v0.2 assets/tag on main and reinstalling the resulting Debian package locally. Keep the release body empty and the existing filenames; do not create another release. Compile/package integrity checks only.

## Notification withdrawal — included in v0.2

- On 2026-10-26 the user tested real mail in the local developer build and confirmed that reading immediately removes the notification from the elementary notification center. They approved publishing this implementation on main and replacing the existing v0.2 Flatpak/Debian assets under the same filenames, with no new release, README or release notes.
- InboxMonitor previously sent notifications but never withdrew them. Raw UID-only notification IDs could also collide across accounts. The new NotificationTracker records notified UID batches by account/inbox scope, generates scoped hashed IDs, and requests GIO withdrawal when all members become SEEN/DELETED or are explicitly removed. Account removal clears its tracked groups. Unknown/unread UIDs do not trigger withdrawal; marking unread again does not re-notify.
- Grouped notifications remain until their last relevant UID is resolved, without reposting partial summaries. Existing badge logic and the canonical Camel inbox object are unchanged. No persistent notification/mail database, panel-cache edit, desktop-specific dependency or extra Flatpak permission.
- Native compile, diff check and the actual tracker logic check passed. A synthetic notification on this elementary 8.1 system remained in the center after popup expiry and disappeared on same-process GIO withdrawal. A separate sender-exit/restart test confirmed that fresh-process GIO withdrawal does not remove the old FDO notification here; synthetic entries were cleaned afterward. No real email data was modified.
- Installed components: io.elementary.notifications 8.1.2+r539+pkg15~ubuntu8.1, indicator 7.1.1+r986+pkg37~ubuntu8.1, GLib 2.80.0-6ubuntu3.10. Exact installed indicator source was downloaded without installation and confirms CloseNotification removes the stored entry. Actual session exposes org.freedesktop.Notifications, not org.gtk.Notifications.
- Important limit: tracking and the native FDO string-to-server-ID mapping are in memory. This patch does not clean notifications from earlier app executions/reboots. Old UID-only notifications cannot reliably be mapped retroactively; manual one-time cleanup is appropriate. Do not claim the generic GIO restart guarantee works on this backend. Fedora/GNOME and Flatpak notification behavior still require user testing.
- Detailed Hungarian report, source links and synthetic probe scripts/logs are in this chat's outputs/notification-research.md and work/notification-research/. Real-mail tests need not be repeated during packaging.

## Reply/forward fidelity — included in v0.3

- User reported missing newsletter content/images and unwanted reply indentation. Composer never enabled remote image loading, body-only DOM export lost head CSS, and source CID resources were not copied into the composer/outgoing MIME.
- A separate get-quote-html WebKit extension command exports the complete rendered body with relevant computed presentation styles inlined, preserving head-defined formatting without leaking global source styles into the composer. Visible DOM, links, image sources, tables and existing inline styles remain. Script/style nodes are omitted after style capture; JavaScript remains disabled and WebKit sandboxing is unchanged.
- Reply's outer cite block has explicit zero margin/padding/border, including in outgoing HTML. Existing nested original quotes retain their formatting.
- Composer enables image requests for quoted content, decodes/registers source CID resources and retains their MIME parts for reply/forward. Outgoing inline resources use multipart/related; regular attachments use outer multipart/mixed. Forward attachment loading completes before composer send controls are restored. Loading is canceled on composer destruction.
- Remote pictures remain remote references; this does not download/embed every external asset for offline viewing. Arbitrary HTML/CSS cannot be promised pixel-identical after editing, but no visible content truncation is introduced.
- User approved the local reply/forward behavior and authorized inclusion in v0.3. Compile/static checks and package integrity checks only; do not repeat functional mail tests.

## Background send — included in v0.3

- User approved reply/forward appearance locally and requested hiding the composer during actual sending, with a subtle main-window status instead of a frozen disabled editor.
- After optional empty-subject confirmation and the existing Undo Send delay, Composer holds the application, hides itself, presents the main window and starts an OSD-style Sending… spinner. Multiple active sends share a count; the status avoids the move-Undo banner. Transport/Sent-folder work remains asynchronous. Application hold is released when the operation finishes.
- Failure restores the complete composer with a modal error; success destroys it. A sent-but-not-saved warning is parented to the main window and does not invite resending.
- The WebKit clean-for-sending command now cleans a cloned DOM instead of deleting IDs/editability from the live editor, preserving retries and continued editing after canceled/failed sending.
- User confirmed background sending works and approved v0.3 publication. Native compilation/static checks only; no real message was sent by automated tests. Error/retry and Undo behavior follow the implementation described above; do not claim separate user verification of those cases.

- Sending status polish: the user confirmed background sending works; its spinner now has an explicit white foreground on the dark status banner.

## Draft-close flow — included in v0.3

- User requested a close confirmation and background IMAP draft saving. The current button semantics are Delete Draft (discard and delete the original saved draft), Edit (continue editing), Save (save a draft). Delete Draft uses REJECT/destructive styling on the left; Edit/CANCEL and Save/ACCEPT/suggested styling are on the right. Escape and dialog close keep editing rather than discard.
- Unchanged composers close directly. Changed body, headers or attachment count prompt; initial reply/forward headers and automatically loaded attachments establish a baseline. Repeated close requests reuse the same dialog. Send and draft-save operations cannot start together.
- Save hides the composer, holds the application during async draft storage and shows the shared dark background-activity banner with a white spinner and Saving draft… label. Sending and draft-save counters coexist. Success closes the retained composer; error restores it with all content and a modal error. No implicit IMAP save on Delete Draft or Edit.
- Shared main-window lookup was extracted from background send; existing sending status/Undo behavior remains. Native compile/static checks only; no automated real-mail changes. User approved the local dialog/IMAP behavior and authorized replacing the existing v0.3 packages on main. Keep the version and filenames unchanged.

### Saved-draft deletion correction — included in v0.3

- User found that both the composer trash confirmation and the custom close-dialog discard only destroyed the editor, leaving its saved IMAP draft untouched. Both now share finish_draft(deleting=true), which asynchronously deletes the original draft before closing. Unsaved new messages simply close without server changes.
- Session.delete_draft validates the original and current DRAFT flags, obtains the original folder from MessageInfo.summary instead of guessing from the selected sender, marks DELETED and synchronizes with expunge. This follows Camel's folder-expunge semantics for messages already flagged DELETED; it is not a custom UID-expunge implementation. On failure the editor is restored and a newly set local DELETED flag is rolled back when the UID still exists.
- Replacing an existing saved draft now uses the same original-folder deletion helper after the new copy is appended successfully.
- Close dialog now says Delete Draft / Edit / Save and matches the stock trash prompt's nonmodal/transient presentation, avoiding the compositor dimming. Repeated prompts and concurrent send/save/delete operations are guarded. Background deletion uses Deleting draft… with the shared white-spinner status.
- Native compile/static checks only; no real drafts were deleted by automated tests. User confirmed the correction works and authorized publication in the existing v0.3 release. Do not repeat real-mail tests while packaging.

## First elementary backport — local, pending user testing (2026-10-31)

- User authorized uninstalling the old application. Removed the `elementary-mail-plus` Debian package without autoremove/purge, stopped its remaining process, and moved the two old autostart desktop files to `~/Projects/butMail-builds/legacy-autostart`. No accounts, secrets or mail data were deleted.
- ConversationList now tracks manual-unread suppression by account/folder/root UID while those conversations remain selected. Mark as Unread cancels any pending read timer before changing flags; selecting another conversation clears that conversation's suppression. Same-selection refresh/re-activation retains the protection. Explicit Mark as Read removes it.
- Automatic read checks the current single selection, scoped identity, suppression and window visibility before acting, including delayed callbacks. Folder/search changes and widget destruction cancel pending timers.
- Native compilation, installation into the local development prefix and whitespace checks passed. Real mail and visual behavior have not been tested by the agent. No new packages, commits or pushes.
- Development launcher: `~/Projects/butMail-builds/run-butmail-dev.sh`; prefix `~/Projects/butMail-builds/local`; build `~/Projects/butMail-builds/native-check`. It exports the new GSettings/data paths. The local WebKit AppArmor profile must be loaded with graphical Polkit after reboot; profile path is `~/Projects/butMail-builds/local/etc/apparmor.d/io.github.IzsakiRobi.butMail.local`.
- Preferences redesign is explicitly included in the remaining sequence; it has not yet been implemented. Let the user test this first correctness backport before piling on unrelated changes.

## Installed elementary butMail — 2026-10-31

- User confirmed the manual-unread fix and requested menu-based installation with the GTK 4 reference icon. Copied the supplied `butMail-reference/src/io.github.IzsakiRobi.butMail.svg` unchanged into this checkout's src/ and replaced the app-icon installation rule with a hicolor scalable SVG. Private elementary action/folder icons remain available.
- Built the renamed `butmail` 0.3 native package from the current local source and installed it through graphical Polkit. Package: `~/Projects/butMail-builds/butmail_0.3_amd64.deb`; packaging source: `~/Projects/butMail-builds/deb-source-0.3`.
- Installed executable `/usr/bin/io.github.IzsakiRobi.butMail`, matching desktop entry, AppArmor profile and exact reference SVG verified. Standard package triggers refreshed application/menu/icon caches. The app can now be started as butMail from the system application menu; no developer shell launcher is needed for normal use.
- Minimal compile/package/install integrity checks only; no automated real-mail or UI tests. No commits, pushes or releases authorized/performed.

## List navigation backport — local, pending user testing (2026-10-31)

- Removed application-wide Delete/Backspace accelerators. ConversationList now handles unmodified Delete/KP_Delete/Backspace only inside the conversation-list widget and invokes the existing enabled Trash action. Search, recipients and editor retain normal text deletion.
- VirtualizingListBox reconciles selection centrally after model updates. If every selected row disappeared or became filtered/hidden, it selects the next visible row at the old first-selected position, or the preceding visible row at the end. Folder/search clears do not select the first row of the newly loaded folder. Partial removals retain surviving selected items.
- Removed the move-only explicit select_row_at_index call, which forced scrolling through ensure_index_visible. Toolbar, context, keyboard and drag moves now share the model-update selection path. Actual server operations and Undo are unchanged.
- Visible widgets are matched and reused by model identity; only rows leaving the rendered range are unparented. Updated heights are applied before filling the viewport. Focus is temporarily retained by the list during reconciliation rather than being left on a row that is being removed; a rendered cursor row receives it afterward without calling ensure_index_visible.
- Native compilation and package build/whitespace checks passed. No automated real-mail actions or UI/scroll tests. The user must verify single/group deletion via toolbar, context menu and keyboard, end-of-list fallback, scrolling during background changes, Undo and normal Delete in text fields.
- Built and reinstalled the local `butmail` 0.3 Debian package through graphical Polkit for menu-based testing. No commit, push, tag or release update. Preferences redesign remains in the planned sequence.

### Delete-key follow-up — pending user test

The user confirmed the toolbar/context Trash operations and list navigation, but Delete/Backspace did not invoke Trash. They clarified that only Delete is wanted. Removed the separate ConversationList EventControllerKey and now handle Delete/KP_Delete through MainWindow.key_press_event, explicitly requiring focus on the conversation-list widget or one of its descendants and an enabled Trash action. This is not an application-wide accelerator; text fields retain native key handling. Backspace is no longer a mail action. The reported event-delivery failure is addressed through the window event path; no runtime key probe or automated real-mail test was run. Native package compilation passed; reinstall and restart use the updated local package. No publication.

## Recipient completion backport — local, pending user testing (2026-10-31)

- User confirmed the Delete-key correction and approved the next implementation step. Added GTK 3 RecipientEntry for To/Cc/Bcc: at least two characters, at most eight suggestions, names/addresses, arrow navigation, Enter acceptance, Tab acceptance with native focus traversal, Shift+Tab/Escape dismissal. Tokens honor quoted names, escaped quotes, commas/semicolons and UTF-8 character positions. Other already-entered recipients in that field are excluded.
- Adapted RecipientStore from the pinned GTK 4 reference with separate in-memory contacts and private history. Contacts rank first, confirmed sends next, chosen suggestions next, Sent/known headers last, with prefix/recency tie-breaking and case-insensitive address deduplication. Contact-only entries neither consume the history budget nor persist. History is pruned to at most 2000 entries when saved; learning has a small transient batching allowance.
- History file: `~/.local/share/io.github.IzsakiRobi.butMail/recipient-history.gv`, private directory/file modes 0700/0600. The system history preference is sampled at construction; when disabled, history is not loaded/learned/written, while contacts remain available. Shutdown flushes pending saves.
- Removed the old Gtk.EntryCompletion path and automatic Folks address-book writes from composing. ContactManager still reads Folks contacts and supplies avatar lookup/updates. Changed/removed contacts rebuild the in-memory suggestion source.
- Successful SMTP submission records the actual recipients privately; failures before successful submission do not. A later Sent-copy/transport-disconnect failure does not erase the successful-submission history. Existing sending/error behavior otherwise remains.
- Composer opening prepares configured Sent folders asynchronously once per folder/session, fetching metadata only. Opened ordinary folders contribute their cached summaries. At most the last 2000 provider-sorted UIDs per folder are considered, with idle yields every 100 entries; parallel scans of the same folder coalesce. Junk/Trash/Drafts roles, virtual folders, configured excluded paths/subtrees and DELETED/JUNK/DRAFT message flags are excluded. No message body download is added for suggestions and no global EDS settings are written.
- Native compilation passed. One isolated no-account data check verified ranking/deduplication, private persistence and limit, separation of contacts, disabled history and quoted/UTF-8 tokens. No UI/account/real-mail tests. The user reiterated minimal automated checks; do not add functional probes. User testing is still required for dropdown appearance, keyboard/mouse acceptance, multiple recipients, Sent-header preparation and subsequent send-history behavior.
- Local package installation is the testing workflow; no Git commit, push or publication is authorized. Settings redesign remains planned.

Recipient backport installed from the local butmail 0.3 Debian package through graphical Polkit; the installed app was restarted for the user to test. No functional test or publication was performed.

### Recipient popup crash correction — pending user retest

The user reported an immediate crash when suggestions appeared. System coredumps for PIDs 33693/33808 show SIGSEGV in g_object_ref from the timeout callback. Generated RecipientEntry.c confirmed that iterating `store.search(query).data` released the temporary GPtrArray before iterating its borrowed pdata. Retain `var suggestions = store.search(query)` for the entire loop instead. The regenerated C now releases this local owner after the loop/function. Native package rebuilt; no UI/account functional probes. Reinstall locally and let the user retest the suggestions. Do not reintroduce temporary-owner `.data` iteration.

## Remaining core roadmap batch — local, pending user tests (2026-10-31)

The user confirmed recipient completion after the lifetime fix and asked to continue efficiently toward finishing the functional roadmap. The three remaining core areas are implemented together to reduce installation cycles. This is not full parity with every optional feature in the reference packet.

- AvatarStore adapts the reference to GdkPixbuf/GTK 3 and the existing Folks photos: contacts -> Gravatar -> Logo.dev -> AnyLogo -> CompanyEnrich -> monogram. Shared requests, cancellation/generation checks, resolution/provider/token-specific keys, one-minute 429 backoff, square/scale-aware decoding without raster upscaling, transparent/CompanyEnrich placeholder rejection, bounded 12-point background sampling and mild white logo inset are retained. Only company domains are queried, with the CompanyEnrich Firefox.com override. The existing image switch still gates contact and remote images. Tooltips identify the source.
- Memory cache is bounded near 256 entries. Private avatars-v4 PNG files expire after seven days; pruning on startup/every 64 writes keeps 512 files with a transient allowance. Old avatars-v3 files are ignored, not migrated/erased. Cache originals before framing. Clear never deletes real contacts. Both list/header inner avatars use 42px with a white ring and deterministic normalized-address SHA256 selection from the reference's 14 flat colors.
- Granite preferences have View / Reading / Acc/Sys pages. New color-scheme schema choice system/light/dark provides immediate preview through GTK settings; Cancel/Escape/destruction restores the saved scheme, Save persists it. Other ordinary preferences remain pending until Save. Explicit key Save/Clear remain independent keyring/cache actions. Existing native accounts/signature editor/storage are retained; outer Cancel does not roll back edits saved in a separate signature window.
- Camel.Transport is reused per outgoing source instead of disconnecting/removing it after successful sends. A per-source async gate serializes connect/submission and releases on success or failure. Failures close the unusable connection and restore the normal composer error; never automatically retry SMTP submission. Existing Sent-copy behavior and EDS/OAuth credential flow are retained. No Fedora GOA password shortcut or speculative real-trash routing change was imported.
- Minimal checks: compilation on the actual elementary/EDS 3.52 stack and GTK 3 CSS parsing. No account, network-provider, sending, UI or visual functional tests. Vala 0.56 cleanup callbacks must be outside finally blocks. User must verify theme/Cancel/Save, layout, avatars and repeated/concurrent sends. No performance claim follows from compilation.
- Optional address-copy HUD, connection dot, reader loading masks and remaining reference visual polish are not part of this core batch. No commits/pushes/releases are authorized. Local package version remains 0.3.

Core roadmap batch installed locally from butmail_0.3_amd64.deb through graphical Polkit and restarted for user testing. No functional probes or GitHub publication.

## Native avatar appearance and duplicate Trash correction — pending user retest

- User approved preferences and single/group move/drag behavior and perceived improved responsiveness. They then requested retaining the stock elementary avatar appearance rather than the reference's flat monograms/white rings. Removed manual palette classes and the appended avatar CSS block, restored native Hdy.Avatar margins and original 40px list / 48px header sizes. Keep the improved lookup/provider/quality/cache backend.
- The screenshot showed custom images becoming blank white circles. The removed CSS globally set background-image:none on avatars, conflicting with Hdy.Avatar's custom image rendering. No cache/account/contact deletion or provider filtering workaround was used.
- User also observed duplicate Trash copies on this native EDS 3.52 installation. Applied the reference's ownership principle: disable use-real-trash-path only in cloned IMAPX runtime settings, retaining real-trash-path and five connections. Flatpak initial setup must not re-enable automatic trash routing; Junk settings are unchanged. No global EDS source writes.
- Shared TrashOperations helpers resolve the real configured physical path independently of automatic provider routing, with virtual-trash fallback when no physical path is configured. Message/folder deletion and Empty Trash use these helpers. Physical Trash role flags remain available independently of Camel's automatic-route flag; redundant virtual Trash rows are skipped in live and cached sidebar paths while a physical destination exists.
- Message moves perform exactly one explicit transfer, then synchronize/expunge the source. A source-cleanup failure reports that the messages moved and does not emit the rollback/retry path or repeat the successful copy. Permanent deletion from the physical Trash and existing delayed Undo semantics are retained. Existing server duplicates are untouched; no subject/Message-ID deduplication.
- Compilation/whitespace checks and local packaging only. No automated mail mutations, provider calls or UI/visual tests. User must verify avatars, one-copy Trash deletion, Undo, deletion within Trash, folder-to-Trash and Empty Trash as desired. No publication is authorized.

Avatar/native-style and Trash-route corrections installed locally and restarted for the user to retest; no mail mutation tests or publication.

## Logo inset and native-style surface polish — pending user visual review

The user confirmed the Trash duplication fix and that logos now render. They requested a small inset for oversized loose logos and a subtle native-looking gradient behind transparent artwork, retaining stock monograms and avoiding a large image-analysis subsystem.

Moved logo framing from provider fetch/cache to the presentation step for all image sources, including Gravatar/contact logos that previously bypassed company-only framing. Keep cached images raw. The existing bounded 12-edge-point classifier preserves filled photos/colored tiles; loose artwork receives about two logical pixels of inset, adjusted to avatar size. Transparent edge samples select a subtle white-to-light-gray background; opaque white artwork keeps white to avoid a visible rectangular seam. No CSS background-image override, new ring or flat monogram palette. No downloads/cache purge or image/visual test suite was used; compilation and local packaging only. User appearance review remains necessary. No publication.

Logo presentation polish installed from the local package via Polkit and restarted for user review; no publication.

### Logo padding follow-up — pending visual retest

User still saw no inset change, particularly Revolut, and requested lighter image shadows, slightly stronger gray borders and a stronger top highlight. Checked libhandy 1.8.3's primary source: size_prepared_cb scales the shorter side to avatar size and make_round_image crops the longer side. The former framing retained rectangular contact-logo aspect ratios, allowing this cover/crop behavior. Loose logos now render on a square canvas with a uniform contain scale and about three logical pixels of inset before Hdy.Avatar crops the circle. Filled images remain unmodified. A narrowly scoped avatar.butmail-avatar.image rule changes only border/shadow/highlight, leaving background-image and stock monograms untouched. No provider downloads, cache deletion or visual test suite. Compile/package locally and let the user compare appearance; no publication.

Square contain padding and scoped image-only border/shadow polish installed locally and restarted for user visual retest. No publication.

Logo polish follow-up: user requested one additional logical pixel of inset (4px total) and withdrew the stronger top-highlight request. Restored the installed elementary theme's stock four inset highlight values while retaining the approved softer outer shadow and slightly grayer image border. Monograms remain untouched. Compile/package/install locally only; user owns visual review.

Star badge polish: user approved the final logo appearance and requested the native elementary yellow gradient/beveled star. The conversation avatar badge now uses the unchanged elementary status/16/starred.svg plus its 2x/3x variants, bundled in the existing private icon theme under its existing license notices. Keep pixel_size=16 (logical pixels). Remove the old symbolic mustard recoloring/shadow and prefer regular icon rendering. No message/star-state logic change, no visual automation or publication.

Composer polish: user approved native star and requested breathing room around recipient suggestions plus excluding formatting controls from Tab traversal. RecipientEntry's scrolled popup content now has 8 logical pixels of top/bottom margin outside its scrolling viewport. EditorToolbar.focus skips only TAB_FORWARD/TAB_BACKWARD, including dynamically added image buttons, while preserving mouse/actions and other keyboard focus directions. The shared signature-editor toolbar receives the same traversal behavior. Compile/package only, user owns functional/visual tests; no publication. Avoid terminating a currently open unsaved composer just to apply this UI update.

Composer Tab follow-up: exclude Cc/Bcc toggle buttons from keyboard focus while retaining mouse activation. Plain Tab from Subject explicitly focuses WebView and its editable message-body element through the existing web-extension channel, skipping intermediate widget/document stops. Shift+Tab and modified Tab retain normal behavior. Compile/package checks only; user verifies interaction. No publication.

Preferences logo sources: remove the avatar lookup-order explanation and static keyring/cache description. View now contains a Logo Sources section with one Sources toggle; its initially collapsed revealer contains the existing Logo.dev key controls, account link and operation status. Status messages reveal the section so save failures remain visible. Credential storage, Save/Clear behavior and provider order are unchanged. Compile/package checks only, user owns visual testing; no publication.

Elementary app icon update: replace src/io.github.IzsakiRobi.butMail.svg with the user-provided ~/Projects/io.github.IzsakiRobi.butMail.svg unchanged. Sync the packaging source and local development prefix; install the same SVG into system hicolor and refresh its icon cache. SVG XML validation only; no application rebuild required and no publication. The previously built .deb must be rebuilt before distribution to include this icon.

Dock Get New Mail action: desktop action invokes --get-new-mail through the existing single-instance application. Remote invocation checks all monitored account inboxes without presenting a window; cold invocation opens the normal app and initial inbox setup refreshes accounts as they become ready. Existing running monitor is reused; missing inboxes retry opening, concurrent per-account refreshes coalesce, and an application hold covers the awaited refresh. No separate daemon or real-mail functional test. Compile/package/install locally only; no publication. This package also includes the latest user-supplied elementary SVG icon.

App icon follow-up: user supplied another revision at ~/Projects/io.github.IzsakiRobi.butMail.svg. Copy it unchanged to active source, packaging source, development prefix and installed system hicolor; refresh icon cache. Rebuild distribution packages before publishing to include this latest revision. No publication.

2026-11-01 size-specific app icons: replace the previous scalable icon with user-supplied 64x64 and 128x128 SVG variants, unchanged, stored as src/icons/<size>/io.github.IzsakiRobi.butMail.svg. Meson installs both to share/icons/hicolor/<size>/apps/<application_id>.svg for native and Flatpak builds. Desktop Icon remains the bare application ID. Remove the obsolete installed scalable variant and refresh caches. Sync packaging source and development prefix. No publication.

2026-11-01 icon bundle refresh: use ~/Projects/Ikoncsomag/hicolor as the latest user-provided artwork. Preserve 48x48@2 (48 logical pixels at scale 2, SVG 96x96), 64x64 and 128x128 directories. All three are copied unchanged to src/icons/<size>/io.github.IzsakiRobi.butMail.svg and installed by Meson into matching hicolor/<size>/apps directories. Sync packaging source/development prefix, rebuild and reinstall local .deb, refresh caches. No publication or UI tests.

Icon scale coverage correction: user explicitly requests all 48x48, 64x64 and 128x128 variants in both normal and @2 hicolor directories. Install all six. The supplied bundle currently contains 48x48@2, 64x64 and 128x128 files; preserve these SVGs unchanged and reuse each size artwork for its missing scale counterpart. Prefer explicit per-scale artwork from future bundles when supplied. Meson, packaging source, development prefix and local installed package all include six variants. No publication.

Icon loader correction: supplied bundle used ns0:svg as its root. Explicit-extension GdkPixbuf file loading worked but automatic PixbufLoader byte sniffing failed with Unrecognized image file format, reproducing the Dock missing icon. Normalize SVG serialization to the default SVG namespace (<svg>), retaining xlink/inkscape namespaces and artwork attributes. Validate automatic loading of every installed variant, not XML parsing/file hashes alone. Original user bundle remains untouched.
