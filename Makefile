# kast — the cast demon
.PHONY: smoke install uninstall pill

smoke:
	bash tests/smoke.sh

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
