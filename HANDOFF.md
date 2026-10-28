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

The connection indicator is an unread-badge-sized dot immediately after the current folder name in the conversation-list header. It is red offline, pulsing blue while connecting, and green connected, with a tooltip and no permanent status label. Refresh is a plain icon and does not dim during work; an activity spinner appears on the footer's right. The send HUD counts down the configured Undo delay. Composer close offers Delete Draft / Edit / Save; the trash button offers Cancel / Delete Draft. Dialogs use a horizontal layout.

The user (call them **rob**, lowercase) performs functional and visual testing. Keep automated checks minimal: compile and only necessary package/static validation. Do not automatically send, move or delete real messages. Use graphical Polkit authentication for system installations and wait for the user. Keep English source/UI and short section comments; remove failed/unused implementation paths. No subagents unless requested. Keep this repository independent; do not reintroduce the legacy reference code or packaging.

This is a working port under active refinement, not a claim of complete feature parity. Further UI polish, real-user testing and remaining original-client features are still pending. In particular, background startup/notifications and remote avatar/account signature integration need further parity review. Releases and source backups do not contain user mail or credentials.
