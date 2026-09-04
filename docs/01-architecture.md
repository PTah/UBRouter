# Архитектура UBrouter

## Компоненты

```text
install.sh
  └─ wizard/main.sh          # фазы 01..13 → answers.yaml
apply path
  └─ scripts/lib/apply.sh    # оркестратор модулей
       └─ modules/*/apply.sh
runtime
  /etc/ubrouter/answers.yaml
  /etc/ubrouter/answers.local.yaml   # секреты (0600)
  /etc/ubrouter/state.json
  /var/lib/ubrouter/snapshots/
```

## Порядок apply-модулей

`interfaces` → `wan` → `lan` → `multi-wan` → `nat-firewall` → `dns-dhcp` → `ntp` → `vpn` → `bypass-policy` → `igmpproxy` → `qos` → `hardening` → `monitoring` → `ospf`

VPN dispatcher всегда вызывает type-модули (`wireguard`, `openvpn`, `gre`, `ipip`, `l2tp`, `ikev2`, `eoip`, `tunnel-ipsec`): пустой список → teardown leftovers.

## Сетевой стек

| Слой | Технология |
|------|------------|
| L2/L3 | netplan + **systemd-networkd** |
| Forward / NAT / fw | nftables (`inet`) |
| DNS + DHCP | dnsmasq |
| NTP | chrony |
| IPv6 RA (LAN) | radvd |
| VPN | WireGuard, OpenVPN, GRE/IPIP/EOIP, strongSwan (IKEv2 + tunnel IPsec), xl2tpd |
| Routing (opt) | FRR OSPF |

## Именование интерфейсов

Фаза 01 — источник правды. Модули не хардкодят `eth0`.

## Snapshot + healthcheck

1. Baseline connectivity.
2. Snapshot конфигов (netplan, nft, dnsmasq, chrony, VPN confs, answers…).
3. Apply.
4. Health window: default **90 с** (PPPoE/rename **~180**); override `UBROUTER_HEALTH_WINDOW`. Регрессия → auto-rollback.

Ручной rollback: `ubrouter rollback`.

## Desired-state cleanup

Повторный apply с выключенным сервисом или без туннеля в answers снимает units/ifaces/managed conf (архив `.ubrouter-disabled`). PKI (`/var/lib/ubrouter/pki`, openvpn-pki) не удаляется.

## State

`state.json`: `version`, `applied_at`, `modules`, `last_snapshot_id`.
