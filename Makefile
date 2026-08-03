# kast — the cast demon
.PHONY: smoke install uninstall pill sync-signers deb check-repo check attack

VERSION := $(shell tr -d '[:space:]' < packaging/VERSION)

# The family's shared recipe layer (sutra.mk, vendored like code under its
# own .version/.commit anchor -- see docs/BOOTSTRAP.md and the file's own
# header, ruling 3e44bd95). Supplies check-sutra (integrity+freshness for
# the vendored .py modules), SUTRA_ROOT_ROWS (the canonical tracked-files
# row count check-repo uses below), and check-vendored-path (the
# checkout-run resolution guard -- generalizes this repo's own earlier
# tests/smoke.sh assertion, one of sutra.mk's two named references). PILL
# must be set before the include; everything else in sutra.mk resolves
# relative to its own vendored location, never this Makefile's.
PILL := kast
include src/share/kast/lib/sutra.mk

# kast is the odd pill in two ways sutra.mk's defaults don't cover: it
# vendors only sutra_update (no daemon, so sutra.py/sutra_xen.py would be
# dead code -- see docs/ARCHITECTURE.md's Standard exemptions), not the
# `sutra` every other pill's default assumes; and the binary that imports
# it isn't named src/bin/kast (sutra.mk's default SUTRA_CHECK_BIN), it's
# src/bin/kast-update -- kast itself (the bash CLI) never touches sutra at
# all. Every other pill gets both defaults for free; kast needs both set.
SUTRA_CHECK_MODULE := sutra_update
SUTRA_CHECK_BIN := src/bin/kast-update

# kast does not vendor pill.js (extension.js has no `import * as Pill from
# './pill.js'`) -- SUTRA_EXT_DIR stays unset on purpose, not an oversight
# (Alfred msg 2761: "your call, and record it either way").

DEBROOT := build/deb/kast_$(VERSION)_all
DEBFILE := build/deb/kast_$(VERSION)_all.deb

smoke: check-sutra
	bash tests/smoke.sh
	bash tests/test_signing.sh

# Mechanical proof that kast still meets REPO-STANDARD.md, the standard it
# was chosen to exemplify (Alfred msg 1724: kast was the only converged pill
# with no such gate — everything Waves 4/5 built was held in place by nobody
# having touched it since, not by anything that could catch drift). Modelled
# on coldspot's check-repo, the family's reference shape.
check-repo:
	@fail=0; \
	for f in README.md LICENSE Makefile install.sh uninstall.sh .gitignore .gitattributes \
	         docs/USAGE.md docs/ARCHITECTURE.md docs/RELEASING.md; do \
	    if [ ! -e "$$f" ]; then echo "check-repo FAIL: missing $$f"; fail=1; fi; \
	done; \
	if [ ! -e src/data/man/man1/kast.1 ]; then \
	    echo "check-repo FAIL: no src/data/man/man1/kast.1"; fail=1; \
	fi; \
	rows=$(SUTRA_ROOT_ROWS); \
	if [ "$$rows" -gt 12 ]; then \
	    echo "check-repo FAIL: root has $$rows rows, standard caps it at 12"; fail=1; \
	else \
	    echo "check-repo: root row count ok ($$rows)"; \
	fi; \
	if ! grep -q '^## Map' README.md 2>/dev/null; then \
	    echo "check-repo FAIL: README.md has no navigation block (## Map)"; fail=1; \
	fi; \
	for h in Troubleshooting "Repo Layout"; do \
	    if grep -q "^## $$h" README.md 2>/dev/null; then \
	        echo "check-repo FAIL: README.md carries a post-install heading ('$$h') that belongs in docs/USAGE.md"; fail=1; \
	    fi; \
	done; \
	if [ ! -f packaging/VERSION ]; then \
	    echo "check-repo FAIL: no packaging/VERSION"; fail=1; \
	fi; \
	if grep -rn "VERSION[[:space:]]*=[[:space:]]*['\"][0-9]" \
	    src/bin/kast src/bin/kast-airplay src/bin/kast-control-center src/bin/kast-healthcheck \
	    src/bin/kast-update src/bin/kast-pill install.sh uninstall.sh \
	    src/extension/kast@asuramaya/extension.js src/extension/kast@asuramaya/prefs.js 2>/dev/null; then \
	    echo "check-repo FAIL: a literal version string exists outside packaging/VERSION"; fail=1; \
	fi; \
	if grep -v '^[[:space:]]*#' .github/workflows/release.yml 2>/dev/null | grep -q -- '--generate-notes'; then \
	    echo "check-repo FAIL: release.yml still uses --generate-notes, not --notes-file"; fail=1; \
	fi; \
	stray=$$(find docs -name '*.md' -not -path '*/.*' | while read -r f; do git ls-files --error-unmatch "$$f" >/dev/null 2>&1 || echo "$$f"; done); \
	if [ -n "$$stray" ]; then \
	    echo "check-repo FAIL: untracked *.md under docs/: $$stray"; fail=1; \
	fi; \
	spec=$$(find . -name '*-SPEC.md' -not -path './.git/*'); \
	if [ -n "$$spec" ]; then \
	    echo "check-repo FAIL: *-SPEC.md left in the repo (specs belong in the seat's office): $$spec"; fail=1; \
	fi; \
	if [ -f docs/ARCHITECTURE.md ] && grep -q '^## Standard exemptions' docs/ARCHITECTURE.md; then \
	    bad=$$(awk '/^## Standard exemptions/{f=1;next} f && /^\|/ && !/^\| *Item *\|/ && !/^\|---/{ n=gsub(/\|/,"|"); if (n<3) print }' docs/ARCHITECTURE.md); \
	    if [ -n "$$bad" ]; then echo "check-repo FAIL: exemptions table has a row missing a column"; fail=1; fi; \
	fi; \
	if [ "$$fail" -eq 0 ]; then echo "check-repo: all mechanical checks passed"; else exit 1; fi

# Canonical family grammar (`smoke attack check deb`): the same static checks
# as CI's lint job, runnable locally in one shot.
# Exclusions are passed as flags, not via an rc file: shellcheck only grew
# --rcfile in 0.11.0, and older builds (including the one on ubuntu-latest)
# reject the flag outright, so an rc file either costs a root row or breaks CI.
# SC2155  declare-and-assign on one line is intentional — `local x="$(cmd)"`
#         deliberately swallows the substitution's status so set -e won't abort.
# SC1090/SC1091  runtime `source` of the user config and dynamic paths cannot
#         be followed statically.
SHELLCHECK_EXCLUDES = SC2155,SC1090,SC1091

check: check-sutra check-vendored-path
	shellcheck -e $(SHELLCHECK_EXCLUDES) install.sh uninstall.sh src/bin/kast src/bin/kast-healthcheck packaging/release-signing/sync-signers.sh tests/smoke.sh tests/test_signing.sh
	python3 -m py_compile src/bin/kast-airplay src/bin/kast-control-center src/bin/kast-update src/share/kast/lib/sutra_update.py
	node --check "src/extension/kast@asuramaya/extension.js" "src/extension/kast@asuramaya/prefs.js"
	python3 -c "import json; json.load(open('src/extension/kast@asuramaya/metadata.json'))"
	groff -t -k -man -Tutf8 -ww src/data/man/man1/kast.1 > /dev/null
	@echo "all static checks passed"

# kast is glue with no daemon and no socket to fuzz (canonical family
# grammar is `smoke attack check deb`; UNIFY.md's attack row). This is a
# recorded exemption, not a silent gap: the target exists on purpose to say
# so, rather than a missing verb the grammar would otherwise imply.
attack:
	@echo "attack: exempt -- kast has no daemon/socket surface to fuzz (see this Makefile comment)"

# rebuild packaging/release-signing/allowed_signers from the canonical keys (see
# docs/RELEASE-SIGNING.md — do NOT run casually; see the sequencing rule there)
sync-signers:
	bash packaging/release-signing/sync-signers.sh

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
	cp -r src/extension/kast@asuramaya $(HOME)/.local/share/gnome-shell/extensions/
	@echo "pill installed — now: gnome-extensions enable kast@asuramaya"
	@echo "then log out and back in once (Wayland reloads extensions at login)"

# .deb: shared/inert files under /usr only. Every ACTIVATION (the pill,
# the Super+K shortcut, a receiver's first enable) stays exactly as per-user
# as the checkout path above — see packaging/deb/postinst and src/bin/kast-pill.
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
	install -d -m 0755 $(DEBROOT)/usr/share/man/man1
	install -d -m 0755 $(DEBROOT)/usr/share/kast/lib
	install -m 0755 src/bin/kast src/bin/kast-airplay src/bin/kast-control-center \
	    src/bin/kast-healthcheck src/bin/kast-update src/bin/kast-pill $(DEBROOT)/usr/bin/
	# kast-update's engine: the family's shared update spine (Wave B
	# convergence, docs/RELEASE-SIGNING.md). Lives in a private per-pill dir,
	# not beside the binaries in the shared /usr/bin — two pills vendoring
	# identically-named sutra_update.py into the same bin dir collide, and
	# dpkg refuses the second package outright (ruling 3e44bd95). kast-update's
	# own bootstrap preamble finds it here at runtime; never hand-edited,
	# re-vendored via sutra's vendor.sh.
	install -m 0644 src/share/kast/lib/sutra_update.py src/share/kast/lib/sutra_update.version $(DEBROOT)/usr/share/kast/lib/
	if [ -f src/share/kast/lib/sutra_update.commit ]; then \
	    install -m 0644 src/share/kast/lib/sutra_update.commit $(DEBROOT)/usr/share/kast/lib/; \
	fi
	install -m 0644 packaging/VERSION $(DEBROOT)/usr/share/kast/VERSION
	install -m 0644 packaging/release-signing/allowed_signers $(DEBROOT)/usr/share/kast/allowed_signers
	install -m 0644 src/data/man/man1/kast.1 $(DEBROOT)/usr/share/man/man1/kast.1
	install -m 0644 src/data/config/uxplay.conf.example $(DEBROOT)/usr/share/kast/uxplay.conf.example
	install -m 0644 src/extension/kast@asuramaya/extension.js \
	    src/extension/kast@asuramaya/prefs.js \
	    src/extension/kast@asuramaya/metadata.json \
	    $(DEBROOT)/usr/share/kast/extension/kast@asuramaya/
	sed 's#@DAEMON_BIN@#/usr/bin/gnome-network-displays-daemon#' \
	    src/data/dbus/org.gnome.NetworkDisplays.Daemon.service \
	    > $(DEBROOT)/usr/share/dbus-1/services/org.gnome.NetworkDisplays.Daemon.service
	install -m 0644 src/data/config/pipewire/50-raop.conf $(DEBROOT)/usr/share/pipewire/pipewire.conf.d/50-raop.conf
	install -m 0644 src/data/applications/kast-center.desktop $(DEBROOT)/usr/share/applications/kast-center.desktop
	for u in uxplay shairport-sync kast-youtube kast-update; do \
	    install -m 0644 src/data/systemd/user/$$u.service $(DEBROOT)/usr/lib/systemd/user/$$u.service; \
	done
	install -m 0644 src/data/systemd/user/kast-update.timer $(DEBROOT)/usr/lib/systemd/user/kast-update.timer
	install -m 0755 packaging/deb/postinst $(DEBROOT)/DEBIAN/postinst
	install -m 0755 packaging/deb/prerm $(DEBROOT)/DEBIAN/prerm
	install -m 0755 packaging/deb/postrm $(DEBROOT)/DEBIAN/postrm
	{ \
	  echo "Package: kast"; \
	  echo "Version: $(VERSION)"; \
	  echo "Section: gnome"; \
	  echo "Priority: optional"; \
	  echo "Architecture: all"; \
	  echo "Depends: python3, jq, systemd, openssh-client"; \
	  echo "Suggests: gnome-shell, avahi-daemon, avahi-utils, gnome-network-displays, network-manager, pipewire-audio, pipewire-pulse, uxplay, wireplumber, wpasupplicant, zenity"; \
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
