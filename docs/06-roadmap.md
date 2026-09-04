# Roadmap

## 1.0.1

- Docs/README синхронизированы с кодом 1.0 (wizard 01–13, VPN matrix shipped, cleanup)
- ТЗ §1: IPv6/OSPF в продукте; public github mirror

## 1.0.0

- Desired-state cleanup: VPN (все типы) + bypass при удалении из answers / Y→N
- `scripts/lib/vpn-cleanup.sh`; dispatcher всегда вызывает type-модули
- Acceptance S17 (VPN/bypass teardown); docs
- VM smoke: минимальный набор в `tests/acceptance.md` (на железе/VM)

## 0.7.2

- Y→N cleanup: dnsmasq/chrony/SQM/igmp/fail2ban/UU (+ disable units, archive conf)
- LAN IPv6 RA: `radvd` when `lan.ipv6.enabled` + address
- OpenVPN: stable `dev ovpn*`; vpn-watch следит за сервером/клиентом
- Schema: monitoring / knock / ospf / multi_mode / lan.ipv6

## 0.7.1

- Wizard: GRE/EOIP/IPIP/L2TP — «чистый» или с IPsec; `vpn/tunnel-ipsec` (strongSwan transport+PSK)

## 0.7.0 — к релизу

- IPv6: wizard + netplan dhcpv6/slaac + LAN ULA + nft/sysctl forward
- PPPoE: vlan/mtu из wizard, nft WAN=`ppp0`, service-name, +ipv6
- EOIP: wait-wan, After=pppoe/gre, routes+metric
- Telegram VPN-notify: IKEv2 updown + GRE/EOIP/WG iface watch
- OSPF: optional FRR wizard `12-ospf`
- Schema validate перед apply; `ubrouter wg-peer`
- Out of product TODO: L2TP server, SIP ALG (руками при необходимости)
- OpenVPN server — уже в 0.6.0

## 0.6.0

- Netwatch + Telegram; port-knock; OpenVPN server; DHCP tags; Multi-WAN LB

## После 1.0 (опционально)

- github orphan publish (`Publish-GithubOrphan`)
- Расширенный VM matrix (все S*)
