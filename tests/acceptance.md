# Приёмочные сценарии (UBrouter ≥ 1.0.0)

Минимальный набор для проверки на **Ubuntu Server 24.04**. Каждый suite независим — удобно гонять на разных VM.

Обозначения:

- **Router** — хост с UBrouter (≥2 NIC, если не указано иное)
- **Client** — LAN-машина за Router
- Команды от root / через `sudo`

Перед silent-apply заполните `interfaces.map` (MAC→name) под VM.

Подробности CLI: [docs/09-doctor-export.md](../docs/09-doctor-export.md).

---

## P — Pre-flight

| # | Сценарий | Команды / условие | Ожидание |
|---|----------|-------------------|----------|
| P1 | Норма | Ubuntu 24.04, 2 NIC, ≥1 ГБ `/var`: `sudo ./install.sh` | preflight OK → wizard |
| P2 | Чужой OS | Debian 12: `sudo ./install.sh` | fail: OS mismatch |
| P3 | `--force` | Debian 12: `sudo ./install.sh --force` | warn, wizard стартует |
| P4 | 1-NIC lab | `UBROUTER_MIN_NICS=1 sudo ./install.sh` | preflight OK |
| P5 | Skip | `sudo ./install.sh --skip-preflight` | skip, wizard сразу |
| P6 | Lock | два `install.sh` параллельно | второй: apply lock занят |

Маленький диск: `UBROUTER_MIN_DISK_MB=512 sudo ./install.sh`.

---

## S1 — Базовый NAT-роутер

Answers: 2 NIC, `naming: keep`, WAN DHCP, LAN `10.0.0.1/24`, NAT + dnsmasq + chrony.

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S1.1 | Apply | `sudo ./install.sh --answers … --apply` | OK за <90 с |
| S1.2 | DHCP | на Client: `dhclient eth0` (или аналог) | IP из пула |
| S1.3 | WAN ping | Client: `ping -c3 1.1.1.1` | OK |
| S1.4 | DNS | Client: `dig @10.0.0.1 one.one.one.one` | OK |
| S1.5 | Doctor | `sudo ubrouter doctor` | OK≥10, WARN≤2, CRIT=0, exit 0 |

---

## S2 — Rename (`ethN`)

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S2.1 | Apply | `naming: eth`, map enp*→eth0/eth1 | apply OK, возможен reboot |
| S2.2 | Без reboot | `ip link show eth0` | есть → OK; нет → reboot |
| S2.3 | После reboot | `ip link show eth0 eth1` | оба есть |
| S2.4 | Doctor | `sudo ubrouter doctor` | interfaces: map OK |

---

## S3 — Bridge LAN

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S3.1 | Apply | 3 NIC: WAN + eth1/eth2→`br-lan` | apply OK |
| S3.2 | Client на eth1 | DHCP | IP из пула |
| S3.3 | Client на eth2 | DHCP без правок answers | IP из пула |
| S3.4 | Bridge | `ip link show br-lan` | UP, slaves eth1+eth2 |

---

## S4 — PPPoE WAN

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S4.1 | Apply | WAN `pppoe`, vlan 35, MTU 1492 | OK, health ~180 с |
| S4.2 | Unit | `systemctl status ubrouter-pppoe` | active |
| S4.3 | Default | `ip route show default` | via `ppp0` |
| S4.4 | MSS | Client: `curl -I https://example.com` | OK |

---

## S5 — Multi-WAN failover

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S5.1 | Apply | WAN1 + WAN2 metric 200, `wan.multi` | `multiwan.conf` есть |
| S5.2 | Active | `cat /var/lib/ubrouter/multiwan.active` | primary (WAN1) |
| S5.3 | Failover | выдернуть кабель WAN1, ~30 с | active→WAN2, logger failover |
| S5.4 | Routes | `ip route show default` | одна metric 10 на WAN2; **нет** stale на WAN1 |
| S5.5 | Failback | вернуть WAN1, ~30 с | active→WAN1 |
| S5.6 | Loss | Client ping во время failover | <5% loss |

---

## S6 — WireGuard

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S6.1 | Apply | `vpn.servers`: wg0 listen 51820, `10.66.0.1/24` | apply OK |
| S6.2 | Unit | `systemctl status wg-quick@wg0` | active |
| S6.3 | Listen | `wg show` | interface UP |
| S6.4 | Peer | телефон → wg0 | handshake, peer в `wg show` |
| S6.5 | LAN | с телефона: `ping 10.0.0.1` | OK |

---

## S7 — IKEv2

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S7.1 | Apply | `type: ikev2`, pool 10.67.0.10–200 | apply OK |
| S7.2 | Client | `sudo ubrouter ikev2-client --name phone --generate-password` | `.p12` + `.pass` |
| S7.3 | Conns | `swanctl --list-conns` | сервер виден |
| S7.4 | Certs | `swanctl --list-certs` | CA + server |
| S7.5 | Phone | импорт `.p12`, Connect | SA в `swanctl --list-sas` |
| S7.6 | LAN | ping LAN GW с телефона | OK |
| S7.7 | ESP | клиент без NAT (публичный IP) | OK (nft ESP/AH) |

---

## S8 — Bypass-policy

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S8.1 | Apply | bypass→wg0, cidrs + domain `example.com` | apply OK |
| S8.2 | Set | `nft list set inet ubrouter_bypass bypass_dst` | CIDR из списка |
| S8.3 | DNS→set | `dig @LAN_GW example.com` | IP попал в set |
| S8.4 | Path | Client curl + `tcpdump -i wg0` | трафик через wg0 |
| S8.5 | Reload | правка списка → `sudo ubrouter bypass-reload` | set обновлён без full apply |
| S8.6 | Fail-open | wg0 down ~30 с | fwmark rule снят |
| S8.7 | Doctor | `sudo ubrouter doctor` | bypass: rule + table default |

---

## S9 — IGMP / IPTV

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S9.1 | Apply | igmpproxy upstream WAN, downstream LAN/br | apply OK |
| S9.2 | Unit | `systemctl status igmpproxy` | active |
| S9.3 | Stream | Client VLC/multicast (если ISP отдаёт) | видео идёт |

---

## S10 — QoS (Cake)

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S10.1 | Apply | `qos.cake_lan=true`, bandwidth 100mbit | apply OK |
| S10.2 | tc | `tc qdisc show dev br-lan` (или LAN if) | cake, ~100Mbit |

---

## S11 — Hardening

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S11.1 | fail2ban | `services.fail2ban: true` → apply | OK |
| S11.2 | Ban | 5× неверный SSH с WAN | IP в jail ~1 ч |
| S11.3 | UU | `unattended_upgrades: true` | security-only updates активны |

---

## S12 — Snapshot / rollback

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S12.1 | Manual | после S1: `sudo ubrouter rollback` | конфиги откачены |
| S12.2 | Snapshot | правка answers → `sudo ubrouter apply` | snapshot + OK |
| S12.3 | Auto | сломать netplan → apply | health fail → auto-rollback ~90 с |
| S12.4 | Doctor | `sudo ubrouter doctor` | snapshots integrity OK |

---

## S13 — SSH-safe apply

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S13.1 | Start | `sudo ubrouter apply` по SSH с LAN | в логе: systemd-run |
| S13.2 | Disconnect | закрыть SSH mid-apply | процесс жив: `journalctl -u ubrouter-apply -f` |
| S13.3 | Done | `systemctl status ubrouter-apply` | inactive, ExitCode 0 |

---

## S14 — Doctor

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S14.1 | Healthy | после S1: `sudo ubrouter doctor` | CRIT=0, exit 0 |
| S14.2 | CRIT | `systemctl stop dnsmasq` → doctor | dns fail, exit 1 |
| S14.3 | Warn | `rm /etc/ubrouter/state.json` → doctor | state warn, дальше идёт |

---

## S15 — Export / import

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S15.1 | Export | после S7: `sudo ubrouter export --out /tmp/bak.tar.gz` | 0600, MANIFEST |
| S15.2 | PKI | `tar -tzf /tmp/bak.tar.gz \| grep pki` | пути PKI есть |
| S15.3 | Import | на VM2: `sudo ubrouter import /tmp/bak.tar.gz --yes` | pre-import snapshot |
| S15.4 | Check | на VM2: `sudo ubrouter doctor`; `swanctl --list-certs` | PKI на месте |
| S15.5 | Strip | `sudo ubrouter export --no-pki --no-secrets` | без pki / answers.local |

---

## S16 — Идемпотентность

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S16.1 | 3× apply | `sudo ubrouter apply` ×3 | все OK |
| S16.2 | LAN CIDR | сменить `lan.cidr` → apply | новая подсеть |
| S16.3 | Off service | `dnsmasq: false` → apply | stopped + disabled |

---

## S17 — VPN / bypass teardown (desired-state)

| # | Сценарий | Команды | Ожидание |
|---|----------|---------|----------|
| S17.1 | GRE on | answers: `vpn.clients` GRE → apply | `ubrouter-gre` active, iface есть |
| S17.2 | GRE off | убрать GRE из answers → apply | unit disabled; `ip tunnel` без gre*; script `.ubrouter-disabled` |
| S17.3 | WG orphan | сервер wg0 → apply; убрать → apply | `wg-quick@wg0` inactive; conf archived |
| S17.4 | Bypass off | `bypass.enabled: true` → apply; затем `false` → apply | нет `nft table inet ubrouter_bypass`; timer disabled |
| S17.5 | tunnel-ipsec | GRE+ipsec → apply; убрать ipsec/GRE → apply | нет `ubrouter-tunnel-ipsec-*.conf` |

PKI (`/var/lib/ubrouter/pki`, openvpn-pki) **не** удаляется при teardown — только runtime/units/conf.

---

## Минимальный smoke (одна VM, ~30 мин)

1. **P1** → wizard или answers  
2. **S1.1–S1.5**  
3. **S14.1**  
4. **S15.1** (без второй VM — только export)  
5. **S16.1** + **S16.3**  
6. **S17.1–S17.2** (или S17.3)  

Остальное — по фичам, которые включаете в проде.
