%define app_path /www/ood/apps/sys/

Name:           ood-util
Version:        13
Release:        1%{?dist}
Summary:        Open on Demand utils

BuildArch:      noarch

License:        MIT
Source:         %{name}-%{version}.tar.bz2

Requires:       ondemand
Requires:       ood-util

# Disable debuginfo
%global debug_package %{nil}

%description
Open on Demand utils

%prep
%setup -q

%build

%install

%__install -m 0755 -d %{buildroot}%{_localstatedir}%{app_path}%{name}
%__install -m 0644 README.md %{buildroot}%{_localstatedir}%{app_path}%{name}/

%files

%{_localstatedir}%{app_path}%{name}

%changelog
* Fri Feb 23 2023 Sami Ilvonen <sami.ilvonen@csc.fi>
- Initial version
