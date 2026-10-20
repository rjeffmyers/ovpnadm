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
sudo ovpnadm client add jane-laptop  # her personal .ovpn, 90 days (CERT_DAYS)
sudo ovpnadm client add vendor --days 30 --until 2027-03-31
                                     # 30-day certificates, never past 31 March
sudo ovpnadm client list             # expiry, days left, renewal rules
sudo ovpnadm client renew jane-laptop
sudo ovpnadm client set vendor --until 2027-06-30   # extend the end date
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

## Who is connected: showvpn

```
showvpn                  # connected users, the port each one dialled, traffic
showvpn -w               # same, refreshed every 5 seconds
showvpn -a               # today's connection attempts per address (whitelisted or not)
showvpn -a "2 hours ago"
showvpn -f               # watch attempts live, e.g. while someone tries to connect
```

It reads every `/var/log/openvpn/status*.log` (a file with `tcp` in its name
is shown as TCP), so it works for ovpnadm servers and for a UDP+TCP pair.
The PORT column comes from connection tracking (package `conntrack`) and shows
the port a client really dialled when other ports are forwarded to the VPN
port. `-a` and `-f` need the attempt log rules that the iptables add-on writes.

## Expiry and rotation

Every personal profile has two rules, set when it is issued and changed with
`client set`:

- **period** (`--days`, default `CERT_DAYS` = 90): how long each certificate
  lasts. Typical: 30, 60, 90 or 365.
- **access-until date** (`--until YYYY-MM-DD`, optional): no certificate, however
  it is renewed, runs past the end of that day. `--no-end` removes it.

A certificate is cut short to end before the access-until date. Moving the date
earlier takes effect at the next renewal, so renew right away to apply it now.

| What | How it ends | Effect |
|---|---|---|
| Personal profile | its certificate expires, or `client revoke` | that one file stops working |
| Every profile | `rotate-key` (new tls-crypt key) | all files stop working, everyone reconnects with a new one |
| Password | `ovpnadm passwd <user>` | that user needs the new password |

The server refuses an expired or revoked certificate when a client connects.
A session already up keeps running until it disconnects, so use `kick` to
end it right away (`client revoke` does this for you).

`client list` shows days left. Renew before expiry to hand over a new file
without a gap.

## Self-service web page

With `PORTAL=yes` (then `ovpnadm install`), connected users can open
`http://10.8.0.1:8080/` (the first address of `VPN_POOL`) and:

- see their profile's expiry, renewal period and access-until date,
- **renew** their profile: from `RENEW_WINDOW` (14) days before expiry, for
  their own period, never past their access-until date. Only the admin can
  extend that date.
- **download** their current profile again (another device, reinstall),
- **change their password** (at least 12 characters). This is off for accounts
  listed in `SHARED_USERS`.

How it stays safe:

- It listens only on the VPN server's tunnel address, so it is not reachable
  from the internet or the LAN.
- The user is identified by the VPN address the request comes from, which
  OpenVPN ties to their session. There is no separate login to attack. Every
  action also asks for the current password, and 5 wrong passwords lock that
  address out for 15 minutes.
- The web process runs as the unprivileged `ovpnadm-portal` user and can only
  run `sudo ovpnadm self ...`, which works out the identity again by itself.
- Actions are logged: `journalctl -t ovpnadm-portal`.
- Plain HTTP is intentional: the traffic already runs inside the encrypted
  tunnel, and a certificate for a private address would only produce browser
  warnings.

Your firewall must accept TCP `PORTAL_PORT` from the tunnel (`tun*`) to that
address.

After a self-service renewal, the user's current connection stays up. The old
profile no longer works for new connections, so the page tells them to import
the new file before disconnecting. If they lose it, they can download it again
while still connected, or the admin can run `client renew`.

## Firewall

ovpnadm does not change the firewall. You need to:

- allow UDP `PORT` (1194) in on the internet-side interface,
- forward traffic from the tunnel (`tun*`) to `LAN_NET`,
- give the LAN a way back to `VPN_POOL`: either a route via this host (which
  is automatic if it is their gateway), or NAT.

Restricting the port to known client IPs is strongly recommended.

## IP whitelist by user

If an `allowvpn` command is installed (it manages a source-IP whitelist for
the VPN port: `allowvpn <ip> [comment]`, `allowvpn -r <ip>`, `allowvpn -l`),
ovpnadm records **which users each address belongs to**, so you can remove
people instead of looking up addresses:

```
sudo ovpnadm whitelist add 203.0.113.25 -u jane home   # allow it for jane
sudo ovpnadm whitelist                                 # addresses, users, logins seen, SHARED
sudo ovpnadm whitelist remove-user jane --dry-run      # what would go
sudo ovpnadm whitelist remove-user jane
```

- An address recorded for several users (an office) is flagged **SHARED**, you
  are warned when adding it for another user, and removing one user keeps it
  for the others.
- The list also shows who has actually **logged in from** each address (from
  the login history), so unrecorded or shared use shows up too.
- `ovpnadm remove <user>` cleans up that user's addresses automatically - handy
  for an offboarding checklist.

The records live in `/var/lib/ovpnadm/whitelist-users`.

## Per-user access for iptables firewalls (iptables-addon)

`iptables-addon/` is for a host whose firewall is a classic iptables script
that flushes everything when it runs. It gives each VPN user a fixed VPN
address and lets them reach **only their own hosts and ports**, the whole LAN
for some, a single RDP desktop for others. Everything else from the tunnel,
including this host, is dropped. It runs a UDP server and a TCP twin
(`openvpn-server@server` and `@tcp`, pools `UDP_NET` / `TCP_NET`), can forward
extra ports (UDP 443, TCP 993) to the VPN port for networks that block 1194, and
pushes a DNS server for one domain without sending internet traffic through
the VPN. The package installs these files in `/usr/share/ovpnadm/iptables-addon/`.

| File | Install as | |
|---|---|---|
| `rc.openvpn` | `/etc/firewall/rc.openvpn` (700) | firewall chains `OVPN_*` and the per-user `ccd-udp/`, `ccd-tcp/` files |
| `rc.openvpn.conf.example` | `/etc/firewall/rc.openvpn.conf` | interfaces, LAN, VPN pools, redirected ports, DNS |
| `access.txt.example` | `/etc/openvpn/server/access.txt` (600) | who may reach what |
| `vpnuser` | `/usr/local/sbin/vpnuser` (700) | manage the accounts and `access.txt` |

Then:

- add `client-config-dir ccd-udp` (`ccd-tcp` in `tcp.conf`) and `ccd-exclusive`
  to the server configs, and remove any `push "route ..."` lines; users without
  a line in `access.txt` can then not connect at all;
- run `/etc/firewall/rc.openvpn` at the end of your firewall script, since that
  script removes the `OVPN_*` chains every time it runs.

```
sudo vpnuser add jane.doe lan                              # whole LAN, all ports
sudo vpnuser add john.roe 192.168.1.120 3389/tcp,3389/udp  # RDP to one desktop
sudo vpnuser set john.roe 192.168.1.121 3389/tcp           # change access
sudo vpnuser passwd jane.doe                               # new random password
sudo vpnuser del john.roe                                  # blocked at once
sudo vpnuser list
```

`vpnuser` makes VPN-only accounts (no shell) in `vpnusers`. Add
`DenyGroups vpnusers` to the sshd config so they cannot use SSH or SFTP from
the LAN either. New passwords are shown and kept in `/root/vpn-passwords.txt`.
A change that `rc.openvpn` rejects is undone. Changes apply at the user's
next connection, except removed access, which is blocked at once.

Clients: OpenVPN Connect on Windows needs `setenv CLIENT_CERT 0` in a profile
without a client certificate (ovpnadm adds it). NetworkManager on Linux sends
all traffic into the tunnel unless the connection is set to *Use only for
resources on this connection* (`ipv4.never-default yes`), and that traffic is
then dropped.

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
| `/var/lib/ovpnadm/whitelist-users` | which users each whitelist address is for |
| `/var/lib/ovpnadm/clients` | each client's renewal period and access-until date |
| `/usr/lib/ovpnadm/portal` | the self-service web page (service `ovpnadm-portal`) |
| `/etc/sudoers.d/ovpnadm-portal` | lets the portal run `ovpnadm self` only |
| `/usr/sbin/showvpn` | who is connected and connection attempts |
| `/usr/share/ovpnadm/iptables-addon/` | per-user access add-on (see above) |

## License

Public domain ([Unlicense](LICENSE)).
