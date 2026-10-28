application_id = 'io.github.IzsakiRobi.butMail'
gnome = import('gnome')
resources = gnome.compile_resources('butmail', 'resources.xml', source_dir: '.')
executable(
    application_id,
    'Application.vala',
    'Models.vala',
    'MailData.vala',
    'MailOperations.vala',
    'BackendFolders.vala',
    'BackendTrash.vala',
    'FolderSidebar.vala',
    'FolderRow.vala',
    'FolderNameDialog.vala',
    'FolderPickerPopover.vala',
    'NewFolderDialog.vala',
    'EmptyState.vala',
    'ConversationList.vala',
    'ConversationView.vala',
    'MessageCard.vala',
    'MessageBody.vala',
    'EnvelopeDragIcon.vala',
    'MainWindow.vala',
    'SplitResizeHandle.vala',
    'ComposeSnapshot.vala',
    'ComposerWindow.vala',
    'DraftDialog.vala',
    'RichTextEditor.vala',
    'PreferencesDialog.vala',
    'SignatureDialog.vala',
    'LogoCredentials.vala',
    'OnlineAccounts.vala',
    'MailSession.vala',
    'MailBackend.vala',
    'MailCache.vala',
    resources,
    dependencies: [
        dependency('gtk4', version: '>=4.12'),
        dependency('libadwaita-1', version: '>=1.6'),
        dependency('webkitgtk-6.0', version: '>=2.42'),
        dependency('libsecret-1'),
        dependency('camel-1.2', version: '>=3.58'),
        dependency('libedataserver-1.2', version: '>=3.58'),
        dependency('libedataserverui4-1.0', version: '>=3.58')
    ],
    install: true
)
install_data(application_id + '.desktop', install_dir: get_option('datadir') / 'applications')
install_data(application_id + '.metainfo.xml', install_dir: get_option('datadir') / 'metainfo')
install_data(application_id + '.gschema.xml', install_dir: get_option('datadir') / 'glib-2.0/schemas')
install_data(application_id + '.svg', install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps')
gnome.post_install(glib_compile_schemas: true, gtk_update_icon_cache: true)
