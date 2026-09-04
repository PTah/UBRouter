# Матрица VPN / туннелей (1.0)

Статусы: **shipped** · **not shipped** · **wont**

## Клиент (роутер → удалённая сторона)

| Протокол | Статус | Пакеты | Заметки |
|----------|--------|--------|---------|
| WireGuard | shipped | `wireguard-tools` | `config_file` → `/etc/wireguard/` |
| OpenVPN | shipped | `openvpn` | import `.ovpn` |
| GRE | shipped | `iproute2` | plain или `ipsec: true` |
| IPIP | shipped | `iproute2` | plain или `ipsec: true` |
| EOIP | shipped | GRE+key | MikroTik; wait-wan; ± IPsec |
| L2TP (+IPsec opt) | shipped | `xl2tpd`, strongSwan | пароли/PSK в answers.local |
| IKEv2 client | shipped | strongSwan | EAP / PSK / pubkey |
| PPPoE | shipped (WAN) | `pppoe` / netplan | не дублировать в `vpn.clients` |
| SIT 6in4 | not shipped | — | |
| ZeroTier / Tailscale | not shipped | — | |
| PPTP | wont | — | небезопасно |
| SSTP | wont | — | |

## Сервер (клиенты → роутер)

| Протокол | Статус | Заметки |
|----------|--------|---------|
| WireGuard | shipped | `ubrouter wg-peer` (+ QR) |
| OpenVPN | shipped | PKI + `.ovpn` (`ubrouter openvpn-client`) |
| IKEv2 | shipped | PKCS#12 (`ubrouter ikev2-client`) |
| L2TP/IPsec server | not shipped | out of product |
| PPTP | wont | |

## IPsec на туннелях (GRE / EOIP / IPIP)

Wizard: «чистый» или «с IPsec». Apply: `vpn/tunnel-ipsec` — strongSwan **transport** + PSK.

```yaml
vpn.clients:
  - { type: gre, name: gre0, remote: 203.0.113.2, ipsec: true }
# answers.local.yaml:
# vpn.tunnel_psks.gre0: "secret"
```

Проверка: `swanctl --list-sas`, `ip -d link show gre0`.

## Cleanup

Удалили туннель из answers → re-apply: unit/iface/conf снимаются.  
Убрали последний GRE/EOIP/IPIP с IPsec → snippets `ubrouter-tunnel-ipsec-*.conf` удаляются.  
PKI не трогается.

## Policy routing

См. модуль `bypass-policy` (fwmark + table + CIDR/domain lists).
