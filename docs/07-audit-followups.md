# Known issues / audit follow-ups

См. также [docs/06-roadmap.md](06-roadmap.md), [tests/acceptance.md](../tests/acceptance.md).

## 1.0.0

| Фича | Где |
|------|-----|
| VPN desired-state cleanup | `vpn/apply.sh` всегда вызывает type-модули; empty → teardown |
| GRE/EOIP/IPIP orphans | `managed-*.list` + disable unit + del tunnels |
| WG / OpenVPN orphans | disable `wg-quick@` / `openvpn-*@` + archive conf |
| L2TP / IKEv2 / tunnel-ipsec | options/swanctl snippets; PKI не удаляется |
| Bypass Y→N | nft table, ip rule/table, dnsmasq snippet, units |
| Helpers | `scripts/lib/vpn-cleanup.sh` |
| Acceptance | S17 teardown |

**Не делаем (out of TODO):** L2TP server, SIP ALG apply, Wi‑Fi, Web UI, PPTP, `.rsc` import.

## 0.7.2

Y→N cleanup (dns/ntp/qos/igmp/hardening), radvd LAN RA, OpenVPN `ovpn*` iface + vpn-watch, schema expand.

## 0.7.0

| Фича | Где |
|------|-----|
| IPv6 wizard + apply | `03-wan-ip`, netplan, nat-firewall |
| PPPoE vlan/mtu/ppp0 | wizard review + wan + nat-firewall plan |
| EOIP wait-wan / metric | `vpn/eoip` |
| VPN Telegram notify | `monitoring.vpn_notify`, IKEv2 updown, vpn-watch |
| OSPF (FRR) | wizard 12 + `modules/ospf` |
| Schema validate | `scripts/lib/validate-answers.sh` |
| WG peer CLI | `ubrouter wg-peer` |

## 0.6.0

| Фича | Где |
|------|-----|
| Netwatch + optional Telegram | `scripts/modules/monitoring/`, wizard 11 |
| Port-knock | wizard 06 + `nat-firewall` |
| OpenVPN server + `.ovpn` | `vpn/openvpn`, `ubrouter openvpn-client` |
| DHCP tags / hosts | wizard 04 + `dns-dhcp` |
| Multi-WAN LB (ECMP) | wizard 03 + `wan.multi_mode: lb` |

Telegram: без пути к `api.telegram.org` (bypass/VPN) — только syslog.

## 0.5.0

README приведён к коду; приёмочные сценарии в `tests/acceptance.md` (P, S1–S16).

## Добавлено в 0.4.8 (после аудита 0.4.7)

| Фича | Где |
|------|-----|
| Pre-flight checks (OS, NICs, disk, sudo, lock) | `scripts/lib/preflight.sh` + `install.sh --force/--skip-preflight` |
| `ubrouter doctor` — диагностика всех модулей | `scripts/lib/doctor.sh` + `ubrouter doctor` |
| `ubrouter export/import` — миграция/backup | `scripts/lib/backup.sh` + `ubrouter export [--out FILE] [--no-pki] [--no-secrets]` |

Подробнее: [docs/09-doctor-export.md](09-doctor-export.md).

## После 1.0 (soft)

- Прогон минимального smoke на VM (P1 + S1 + S14 + S16 + S17)
- github orphan при публичном зеркале
- nft input rules для WG/OVPN: reconcile через именованный chain (сейчас best-effort add)
