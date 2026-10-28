Name:           butMail
Version:        0.5
Release:        1%{?dist}
Summary:        Nothing but Mail :)
License:        GPL-3.0-or-later
URL:            https://github.com/IzsakiRobi/butMail
Source0:        butMail-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  vala
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  desktop-file-utils
BuildRequires:  pkgconfig(gtk4) >= 4.12
BuildRequires:  pkgconfig(libadwaita-1) >= 1.6
BuildRequires:  pkgconfig(webkitgtk-6.0) >= 2.42
BuildRequires:  pkgconfig(libsoup-3.0)
BuildRequires:  pkgconfig(gdk-pixbuf-2.0)
BuildRequires:  pkgconfig(libebook-1.2)
BuildRequires:  pkgconfig(libsecret-1)
BuildRequires:  pkgconfig(camel-1.2) >= 3.58
BuildRequires:  pkgconfig(libedataserver-1.2) >= 3.58
BuildRequires:  pkgconfig(libedataserverui4-1.0) >= 3.58
Requires:       gnome-online-accounts
Requires:       evolution-data-server
Requires:       hicolor-icon-theme

%description
A GTK 4 and libadwaita email client using GNOME Online Accounts and
Evolution Data Server. Nothing but Mail :)

%prep
%autosetup -n butMail-%{version}

%build
%meson
%meson_build

%install
%meson_install

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/io.github.IzsakiRobi.butMail.desktop

%files
%license COPYING
%doc README.md butMail-logo.png
%{_bindir}/io.github.IzsakiRobi.butMail
%{_datadir}/applications/io.github.IzsakiRobi.butMail.desktop
%{_datadir}/metainfo/io.github.IzsakiRobi.butMail.metainfo.xml
%{_datadir}/glib-2.0/schemas/io.github.IzsakiRobi.butMail.gschema.xml
%{_datadir}/icons/hicolor/scalable/apps/io.github.IzsakiRobi.butMail.svg

%changelog
* Wed Oct 28 2026 IzsakiRobi <15942662+IzsakiRobi@users.noreply.github.com> - 0.5-1
- Introduce butMail with the GTK 4 and libadwaita interface.
- Refine avatars, message rendering, draft dialogs and tabbed preferences.
