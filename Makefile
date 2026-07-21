# kast — the cast demon
.PHONY: smoke install uninstall pill sync-signers deb

VERSION := $(shell tr -d '[:space:]' < VERSION)
DEBROOT := build/deb/kast_$(VERSION)_all
DEBFILE := build/deb/kast_$(VERSION)_all.deb

smoke:
	bash tests/smoke.sh
	bash tests/test_signing.sh

# rebuild release-signing/allowed_signers from the canonical keys (see
# docs/RELEASE-SIGNING.md — do NOT run casually; see the sequencing rule there)
sync-signers:
	bash tools/sync-signers.sh

# kast has no root half: install.sh is user-scope end to end (it sudos
# internally for apt only). Running it AS root would install into root's
# $HOME — refuse and say so.
install:
	@if [ "$$(id -u)" -eq 0 ]; then \
		echo "make install must NOT run as root — kast installs into your own \$$HOME."; \
		echo "run it as yourself: make install   (or: ./install.sh; it sudos for apt only)"; \
		echo "(the GNOME pill is its own no-root step too: make pill)"; \
		exit 1; \
	else \
		bash ./install.sh; \
	fi

uninstall:
	@if [ "$$(id -u)" -eq 0 ]; then \
		echo "make uninstall must NOT run as root — kast lives in your own \$$HOME."; \
		echo "run it as yourself: make uninstall   (or: ./uninstall.sh)"; \
		exit 1; \
	else \
		bash ./uninstall.sh; \
	fi

# the pill only ever needs your own $$HOME and gnome-shell session — never root
pill:
	mkdir -p $(HOME)/.local/share/gnome-shell/extensions
	cp -r shell-extension/kast@asuramaya $(HOME)/.local/share/gnome-shell/extensions/
	@echo "pill installed — now: gnome-extensions enable kast@asuramaya"
	@echo "then log out and back in once (Wayland reloads extensions at login)"

# .deb: shared/inert files under /usr only. Every ACTIVATION (the pill,
# the Super+K shortcut, a receiver's first enable) stays exactly as per-user
# as the checkout path above — see packaging/deb/postinst and bin/kast-pill.
# Builds only; never installs the result (see tests/smoke.sh's deb check).
deb:
	rm -rf $(DEBROOT)
	install -d -m 0755 $(DEBROOT)/DEBIAN
	install -d -m 0755 $(DEBROOT)/usr/bin
	install -d -m 0755 $(DEBROOT)/usr/share/kast/extension/kast@asuramaya
	install -d -m 0755 $(DEBROOT)/usr/share/dbus-1/services
	install -d -m 0755 $(DEBROOT)/usr/share/pipewire/pipewire.conf.d
	install -d -m 0755 $(DEBROOT)/usr/share/applications
	install -d -m 0755 $(DEBROOT)/usr/lib/systemd/user
	install -m 0755 bin/kast bin/kast-airplay bin/kast-control-center \
	    bin/kast-healthcheck bin/kast-update bin/kast-pill $(DEBROOT)/usr/bin/
	install -m 0644 VERSION $(DEBROOT)/usr/share/kast/VERSION
	install -m 0644 config/uxplay.conf.example $(DEBROOT)/usr/share/kast/uxplay.conf.example
	install -m 0644 shell-extension/kast@asuramaya/extension.js \
	    shell-extension/kast@asuramaya/prefs.js \
	    shell-extension/kast@asuramaya/metadata.json \
	    $(DEBROOT)/usr/share/kast/extension/kast@asuramaya/
	sed 's#@DAEMON_BIN@#/usr/bin/gnome-network-displays-daemon#' \
	    dbus/org.gnome.NetworkDisplays.Daemon.service \
	    > $(DEBROOT)/usr/share/dbus-1/services/org.gnome.NetworkDisplays.Daemon.service
	install -m 0644 config/pipewire/50-raop.conf $(DEBROOT)/usr/share/pipewire/pipewire.conf.d/50-raop.conf
	install -m 0644 applications/kast-center.desktop $(DEBROOT)/usr/share/applications/kast-center.desktop
	for u in uxplay shairport-sync kast-youtube kast-update; do \
	    install -m 0644 systemd/user/$$u.service $(DEBROOT)/usr/lib/systemd/user/$$u.service; \
	done
	install -m 0644 systemd/user/kast-update.timer $(DEBROOT)/usr/lib/systemd/user/kast-update.timer
	install -m 0755 packaging/deb/postinst $(DEBROOT)/DEBIAN/postinst
	install -m 0755 packaging/deb/prerm $(DEBROOT)/DEBIAN/prerm
	install -m 0755 packaging/deb/postrm $(DEBROOT)/DEBIAN/postrm
	{ \
	  echo "Package: kast"; \
	  echo "Version: $(VERSION)"; \
	  echo "Section: gnome"; \
	  echo "Priority: optional"; \
	  echo "Architecture: all"; \
	  echo "Depends: python3, jq, openssh-client"; \
	  echo "Recommends: gnome-shell, uxplay, gnome-network-displays, avahi-utils, zenity, pipewire-pulse, network-manager, wireplumber"; \
	  echo "Maintainer: asuramaya <asuramaya@users.noreply.github.com>"; \
	  echo "Homepage: https://github.com/asuramaya/kast"; \
	  echo "Description: Win+K-style cast panel for GNOME"; \
	  echo " kast brings a Windows Win+K-style cast panel to GNOME as a native"; \
	  echo " Quick Settings tile: AirPlay/Chromecast/Miracast out, and optional"; \
	  echo " off-by-default AirPlay/YouTube receivers in. Per-user glue, never"; \
	  echo " root -- run 'kast-pill install' as yourself after installing this"; \
	  echo " package to activate the pill on your account. Note: dpkg -r cleans"; \
	  echo " /usr but per-user kast-pill copies survive in each account's home --"; \
	  echo " run 'kast-pill remove' per account before purging."; \
	} > $(DEBROOT)/DEBIAN/control
	mkdir -p build/deb
	dpkg-deb --root-owner-group --build $(DEBROOT) $(DEBFILE)
	( cd build/deb && sha256sum "$$(basename $(DEBFILE))" > SHA256SUMS )
	@echo "-- built $(DEBFILE)"
	@command -v lintian >/dev/null 2>&1 && lintian $(DEBFILE) || echo "-- lintian not installed, skipping"
