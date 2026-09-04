# Опросник UBrouter — flow (фазы 01–13)

Язык интерфейса: русский.

Каждый вопрос: default в `[скобках]`, Enter = default.

---

## 01. Интерфейсы

1. Таблица NIC (name, MAC, UP/DOWN, speed).
2. Переименовать? `keep` / `eth0..N` / `ether0..N` / вручную.
3. Порядок портов: `pci` / `mac` / вручную.
4. Подтверждение карты MAC→name → answers / `interfaces.map`.

## 02. Роли WAN / LAN

1. WAN-порт(ы).
2. LAN: один порт или bridge (`br-lan`).
3. Опционально mgmt-порт (без DHCP UBrouter).

## 03. WAN IP

1. Режим: `dhcp` / `static` / `pppoe` / `none`.
2. VLAN id? MTU?
3. **IPv6:** `off` / `dhcpv6` / `slaac`.
4. **Multi-WAN:** дополнительные uplink; режим `failover` или `lb` (ECMP).

PPPoE-пароль — в `answers.local.yaml`.

## 04. LAN

1. CIDR шлюза [`10.0.0.1/24`].
2. DHCP: пул, lease; DNS/NTP клиентам (`router` / upstream / list).
3. Domain [`lan`].
4. Опционально: **DHCP tags** / static **hosts** (MAC→IP/tag).
5. LAN IPv6 ULA + RA (`radvd`), если включено.

## 05. Службы

NAT, firewall, dnsmasq, chrony, upstream DNS — Y/n по согласию.

## 06. Firewall extras

- Port forwards
- SSH с WAN: deny / allowlist / **port-knock**
- fail2ban; SIP ALG (флаг; apply stub — руками при необходимости)
- ICMP WAN

## 07. VPN

1. VPN-клиент(ы)? типы: WireGuard, OpenVPN, GRE, IPIP, EOIP, L2TP, IKEv2.
2. Для GRE/EOIP/IPIP/L2TP: **чистый** или **с IPsec** (PSK → `answers.local`).
3. VPN-сервер? WireGuard / OpenVPN / IKEv2 (+ клиенты / peers).
4. Маршруты / MSS.

PPTP: отказ (небезопасно).

## 08. Bypass / policy routing

Selective bypass? target tunnel, CIDR/domain files, fwmark, table, LAN-only, fail-open.

После базы: `ubrouter bypass` / `bypass-reload`.

## 09. QoS

Cake на LAN? bandwidth?

## 10. IGMP / IPTV

igmpproxy: upstream / downstream / quickleave / altnet.

## 11. Hardening + monitoring

unattended-upgrades; **Netwatch** (+ optional Telegram); **VPN Telegram notify**.

Секреты Telegram — только `answers.local.yaml`.

## 12. OSPF (optional)

Включить FRR OSPF? router-id, areas, interfaces.

## 13. Review

Summary → сохранить answers → «Применить сейчас?» → baseline → snapshot → apply → health (90–180 с) → auto-rollback при регрессии.

---

## Non-interactive

```bash
./install.sh --answers /path/to/answers.yaml --apply
./install.sh --answers /path/to/answers.yaml --plan
```

Секреты: `answers.local.yaml` (merge), права 0600.
