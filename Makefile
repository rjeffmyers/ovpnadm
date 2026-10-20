VERSION := $(shell sed -n 's/^VERSION=//p' ovpnadm)
PKG     := build/ovpnadm_$(VERSION)_all.deb
ROOT    := build/root

.PHONY: deb check clean

deb: $(PKG)

ADDON   := $(wildcard iptables-addon/*)

$(PKG): ovpnadm tui portal showvpn $(ADDON) ovpnadm.conf debian/control debian/conffiles debian/postinst README.md LICENSE
	rm -rf $(ROOT)
	install -D -m 755 ovpnadm $(ROOT)/usr/sbin/ovpnadm
	install -D -m 755 tui $(ROOT)/usr/lib/ovpnadm/tui
	install -D -m 755 portal $(ROOT)/usr/lib/ovpnadm/portal
	install -D -m 755 showvpn $(ROOT)/usr/sbin/showvpn
	install -d $(ROOT)/usr/share/ovpnadm/iptables-addon
	install -m 644 $(ADDON) $(ROOT)/usr/share/ovpnadm/iptables-addon/
	install -D -m 644 ovpnadm.conf $(ROOT)/etc/ovpnadm.conf
	install -D -m 644 README.md $(ROOT)/usr/share/doc/ovpnadm/README.md
	install -D -m 644 LICENSE $(ROOT)/usr/share/doc/ovpnadm/copyright
	install -d $(ROOT)/DEBIAN
	sed 's/@VERSION@/$(VERSION)/' debian/control > $(ROOT)/DEBIAN/control
	install -m 644 debian/conffiles $(ROOT)/DEBIAN/conffiles
	install -m 755 debian/postinst $(ROOT)/DEBIAN/postinst
	dpkg-deb --root-owner-group --build $(ROOT) $@

check:
	bash -n ovpnadm && bash -n tui && bash -n showvpn
	bash -n iptables-addon/rc.openvpn && bash -n iptables-addon/vpnuser
	python3 -m py_compile portal && rm -rf __pycache__
	@command -v shellcheck >/dev/null && shellcheck -x ovpnadm tui showvpn iptables-addon/rc.openvpn iptables-addon/vpnuser || echo "shellcheck not installed; syntax only"

clean:
	rm -rf build
