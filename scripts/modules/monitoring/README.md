# monitoring / netwatch / VPN notify

## Netwatch

Ping узлов из `monitoring.netwatch.hosts`.

## VPN Telegram notify

`monitoring.vpn_notify.enabled: true`:

- **IKEv2:** swanctl `updown` → `/usr/local/sbin/ubrouter-vpn-updown-ikev2.sh`
- **GRE / EOIP / WireGuard:** timer `ubrouter-vpn-watch` (link up/down)

Общий отправитель: `/usr/local/sbin/ubrouter-telegram-send.sh` (env `/etc/ubrouter/netwatch.env`).

**Важно:** `api.telegram.org` часто недоступен без обхода — нужен bypass/VPN с роутера.
