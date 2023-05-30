%define util_path /var/www/ood/deps/util/
%define assets_path /var/www/ood/assets/

Name:           ood-util
Version:        2
Release:        1%{?dist}
Summary:        Open on Demand utils

BuildArch:      noarch

License:        MIT
Source:         %{name}-%{version}.tar.bz2

Requires:       ondemand

# Disable debuginfo
%global debug_package %{nil}

%description
Open on Demand utils

%prep
%setup -q

%build

%install

%__install -m 0755 -d %{buildroot}%{util_path}attributes
%__install -m 0755 -d %{buildroot}%{util_path}forms
%__install -m 0755 -d %{buildroot}%{util_path}scripts/tests
%__install -m 0755 -d %{buildroot}%{assets_path}scripts

%__install -m 0644 -D attributes/*.rb %{buildroot}%{util_path}attributes
%__install -m 0644 -D forms/*.js      %{buildroot}%{assets_path}/scripts/
%__install -m 0644 -D scripts/*.rb    %{buildroot}%{util_path}scripts
%__install -m 0644 -D scripts/tests/* %{buildroot}%{util_path}scripts/tests
%__install -m 0644 form_validation.md README.md LICENSE %{buildroot}%{util_path}/

%files

%{util_path}
%{assets_path}

%changelog
* Fri Mar 3 2023 Robin Karlsson <robin.karlsson@csc.fi>
- Basic working version of RPM

* Thu Feb 23 2023 Sami Ilvonen <sami.ilvonen@csc.fi>
- Initial version
