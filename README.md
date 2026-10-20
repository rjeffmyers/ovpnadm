# ovpnadm

Set up and run an OpenVPN server whose users log in with their **local Linux
username and password**, from a `dialog` menu or the command line.

- Logins are checked by PAM, and only members of one group (`vpnusers`) can connect.
- **Personal, expiring profiles** (default): each person gets their own `.ovpn`
  with a client certificate that expires after `CERT_DAYS` (90). One person can
  be revoked without touching anyone else. Connecting needs the file *and* a
  password.
- Or **one shared profile** for everyone (`CLIENT_CERTS=no`), retired all at
  once with `rotate-key`.
- Split tunnel: clients reach only the LAN you choose.
- You can see connected users and drop their sessions, read the login history
  (successes and failures) and follow the live server log.
- Key backup and restore, so a rebuilt server still accepts the profiles you
  already handed out.

Tested on Ubuntu 22.04 (OpenVPN 2.5, easy-rsa 3.0.8).

## Install

```sh
make deb
sudo apt install ./build/ovpnadm_1.0.0_all.deb
sudo ovpnadm            # menu: Settings, then Install / apply settings
```

Installing the package configures nothing by itself. Settings live in
`/etc/ovpnadm.conf`, and empty values are detected (internet interface from
the default route, public IP, LAN from the other interface).

## Command line

```
sudo ovpnadm install                 # set up / apply /etc/ovpnadm.conf
sudo ovpnadm add jane                # VPN user; prints a random password
sudo ovpnadm client add jane-laptop  # her personal .ovpn, valid CERT_DAYS
sudo ovpnadm client add vendor 30    # ... or valid 30 days
sudo ovpnadm client list             # certificates and days left
sudo ovpnadm client renew jane-laptop
sudo ovpnadm client revoke vendor    # stops working immediately
sudo ovpnadm status                  # who is connected
sudo ovpnadm users                   # VPN users, sessions, last login
sudo ovpnadm kick jane
sudo ovpnadm auth-log                # logins and failed logins
sudo ovpnadm log -f
sudo ovpnadm rotate-key              # retire EVERY issued .ovpn at once
sudo ovpnadm backup keys.tgz         # restore with: ovpnadm install -r keys.tgz
```

Run `ovpnadm help` for everything.

## Expiry and rotation

| What | How it ends | Effect |
|---|---|---|
| Personal profile | its certificate expires (`CERT_DAYS`), or `client revoke` | that one file stops working |
| Every profile | `rotate-key` (new tls-crypt key) | all files stop working, everyone reconnects with a new one |
| Password | `ovpnadm passwd <user>` | that user needs the new password |

The server refuses an expired or revoked certificate when a client connects.
A session already up keeps running until it disconnects, so use `kick` to
end it right away (`client revoke` does this for you).

`client list` shows days left. Renew before expiry to hand over a new file
without a gap.

## Firewall

ovpnadm does not change the firewall. You need to:

- allow UDP `PORT` (1194) in on the internet-side interface,
- forward traffic from the tunnel (`tun*`) to `LAN_NET`,
- give the LAN a way back to `VPN_POOL`: either a route via this host (which
  is automatic if it is their gateway), or NAT.

If an `allowvpn` command is installed (a source-IP whitelist for the VPN
port), the menu and `ovpnadm whitelist` use it. Restricting the port to known
client IPs is strongly recommended.

## Switching an existing server to personal profiles

```sh
sudo ovpnadm config set CLIENT_CERTS yes
sudo ovpnadm install -f              # every existing .ovpn stops working
sudo ovpnadm client add <name>       # one per person
```

`install` refuses to change the login mode without `-f`.

## Files

| Path | |
|---|---|
| `/etc/ovpnadm.conf` | settings |
| `/etc/openvpn/server/server.conf` | written by `ovpnadm install` |
| `/etc/openvpn/server/easy-rsa/` | CA and certificates |
| `/etc/pam.d/openvpn` | login check (password + group) |
| `/run/openvpn-server/mgmt.sock` | management socket (root only) |

## License

Public domain ([Unlicense](LICENSE)).
