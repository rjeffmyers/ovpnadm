VERSION := $(shell sed -n 's/^VERSION=//p' ovpnadm)
PKG     := build/ovpnadm_$(VERSION)_all.deb
ROOT    := build/root

.PHONY: deb check clean

deb: $(PKG)

$(PKG): ovpnadm tui ovpnadm.conf debian/control debian/conffiles debian/postinst README.md LICENSE
	rm -rf $(ROOT)
	install -D -m 755 ovpnadm $(ROOT)/usr/sbin/ovpnadm
	install -D -m 755 tui $(ROOT)/usr/lib/ovpnadm/tui
	install -D -m 644 ovpnadm.conf $(ROOT)/etc/ovpnadm.conf
	install -D -m 644 README.md $(ROOT)/usr/share/doc/ovpnadm/README.md
	install -D -m 644 LICENSE $(ROOT)/usr/share/doc/ovpnadm/copyright
	install -d $(ROOT)/DEBIAN
	sed 's/@VERSION@/$(VERSION)/' debian/control > $(ROOT)/DEBIAN/control
	install -m 644 debian/conffiles $(ROOT)/DEBIAN/conffiles
	install -m 755 debian/postinst $(ROOT)/DEBIAN/postinst
	dpkg-deb --root-owner-group --build $(ROOT) $@

check:
	bash -n ovpnadm && bash -n tui
	@command -v shellcheck >/dev/null && shellcheck -x ovpnadm tui || echo "shellcheck not installed; syntax only"

clean:
	rm -rf build
