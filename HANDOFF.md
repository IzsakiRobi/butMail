# butMail — current handoff, 2026-10-28

## Current project

- Name: **butMail**, exact case. Tagline: **Nothing but Mail :)**.
- Repository: https://github.com/IzsakiRobi/butMail; version 0.5.
- Source: `~/Projects/butMail`; external builds: `~/Projects/butMail-builds`.
- Application, desktop and schema ID: `io.github.IzsakiRobi.butMail`.
- App icon: `src/io.github.IzsakiRobi.butMail.svg`, provided by the user as `~/Projects/butMail.svg`.
- The active build is GTK 4/libadwaita, Vala, WebKitGTK 6, Camel/EDS with GTK 4 credential UI and libsecret. Meson builds only `src/`. Retain the original licenses and attribution on reused code.
- See `BUILDING.md` and `packaging/butMail.spec` for source/RPM builds. The README intentionally contains only the name and tagline.

## Current implementation and constraints

The UI has three adaptive columns, thin resize borders, collapsible stacked message cards, rich-text composing, preferences, folder ordering/menus, mail drag/drop, background operations, Undo and draft dialogs. Real GNOME Online Accounts/EDS mail is connected. Folder snapshots, Camel summaries/bodies and a bounded in-memory rendered conversation cache avoid repeated loading. IMAP concurrency is five. SMTP transports and WebKit network sessions are reused.

The connection indicator is an unread-badge-sized dot immediately after the current folder name in the conversation-list header. It is red offline, pulsing blue while connecting, and green connected, with a tooltip and no permanent status label. Refresh is a plain icon and does not dim during work; an activity spinner appears on the footer's right. The send HUD counts down the configured Undo delay. Composer close offers Delete Draft / Edit / Save; the trash button offers Cancel / Delete Draft. Draft confirmations use native Adw.AlertDialog layouts, with Keep Editing/Cancel as the default response and destructive styling only on Delete Draft.

The user (call them **rob**, lowercase) performs functional and visual testing. Keep automated checks minimal: compile and only necessary package/static validation. Do not automatically send, move or delete real messages. Use graphical Polkit authentication for system installations and wait for the user. Keep English source/UI and short section comments; remove failed/unused implementation paths. No subagents unless requested. Keep this repository independent; do not reintroduce the legacy reference code or packaging.

This is a working port under active refinement, not a claim of complete feature parity. Further UI polish, real-user testing and remaining original-client features are still pending. In particular, background startup/notifications need further parity review. Releases and source backups do not contain user mail or credentials.

## Current local development changes

The WebKit reader/editor use a native centered loading mask with a spinner. Background colors are set before HTML loading; the WebView background is transparent over a solid native editor/reader background, so initial unpainted buffers can blend with the surrounding surface. This targets the light-theme black flash without renderer overrides; user verification remains necessary. Draft dialogs use the native Adwaita layout without a document icon; the initial default response is Keep Editing/Cancel.

AvatarStore/SenderAvatar now implement the address book → Gravatar → Logo.dev → AnyLogo → monogram chain, shared bounded request caching, private disk caching and the remote-avatar preference. Free-provider raster logos must be square and at least 128 px; vectors must be square. See BUILDING.md for provider references.

Collapsed message cards and their bodies explicitly disable vertical expansion. Theme selection previews immediately and Cancel restores the saved style. Sender avatars share a 42 px inner image and a 2 px white ring (46 px total) in list rows and message headers, with flat monogram colors. Unread/star badges follow the larger ring.

Monogram colors are selected deterministically from the normalized sender address using SHA-256 and a 14-color flat palette. All avatar images use the same native circular fill without additional logo padding; the user prefers consistent size even when the circle crops logo corners.

The application menu uses the stock emblem-system-symbolic gear icon. With the sidebar hidden, it is the leftmost footer control, followed by Refresh. Account status and detected accounts are native rows in one PreferencesGroup, without a nested boxed list.

Preferences now have three native ViewStack/ViewSwitcher pages: View, Reading, and Acc/Sys. Run in Background is at the bottom of Accounts / System. Per-account HTML signatures use the account-signatures dictionary keyed by normalized sender email; the previous shared signature remains a fallback. Edits stay pending until Preferences are saved, and the composer inserts the selected sender's signature. Draft confirmation focus outlines are suppressed initially, then native keyboard focus styling resumes on Tab/Shift+Tab; default/close actions remain Keep Editing/Cancel.

The user approved publishing the current refinements to main and replacing the v0.5 binary RPM release on 2026-10-28. The README displays the supplied logo at 256 × 256 px with a centered title and tagline. Future changes still require review and explicit approval before publication. Notifications are the next implementation task.
