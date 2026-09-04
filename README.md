# UBrouter

Интерактивный установщик: **Ubuntu Server 24.04 → полноценный маршрутизатор**.

Wizard пишет `answers.yaml`, затем модульный apply поднимает WAN/LAN, NAT/firewall, DNS/DHCP/NTP, VPN, QoS, IGMP, OSPF и мониторинг. Повторный apply идемпотентен; удаление туннеля или выключение сервиса в answers снимает units/конфиги (desired-state cleanup).

**Обход блокировок:** модуль `bypass-policy` в том же wizard; точечно: `sudo ./ubrouter bypass`.

## Требование: passwordless sudo

Apply меняет сеть от root. Пользователь запуска должен уметь `sudo` **без пароля**:

```bash
# от root — подставьте свой логин
cat >/etc/sudoers.d/ubrouter <<'EOF'
YOUR_USER ALL=(root) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/ubrouter
visudo -cf /etc/sudoers.d/ubrouter
sudo -n -u YOUR_USER true   # проверка
```

Подробнее: [docs/00-tz.md](docs/00-tz.md) §2.8 и [docs/05-security.md](docs/05-security.md).

## Быстрый старт

На Ubuntu 24.04 с ≥2 NIC:

```bash
sudo ./install.sh
# silent:
sudo ./install.sh --answers configs/answers.example.yaml --apply
```

Перед silent-apply в answers заполните `interfaces.map` (список MAC→name в YAML, см. `configs/answers.example.yaml`) или дайте wizard сделать это сам.

CLI:

```bash
sudo ./ubrouter status
sudo ./ubrouter version
sudo ./ubrouter plan            # только plan (без apply)
sudo ./ubrouter apply
sudo ./ubrouter rollback
sudo ./ubrouter bypass          # только bypass-policy
sudo ./ubrouter bypass-reload   # списки обхода без full apply
sudo ./ubrouter ikev2-client    # PKCS#12 для телефона/ноутбука
sudo ./ubrouter openvpn-client  # .ovpn для OpenVPN server
sudo ./ubrouter wg-peer         # новый WireGuard peer (+ --qr)
sudo ./ubrouter doctor
sudo ./ubrouter export          # backup tar.gz (с ключами!)
sudo ./ubrouter import FILE
sudo ./ubrouter install-cli     # /usr/local/lib/ubrouter + /usr/local/sbin/ubrouter
```

Перед wizard/apply — **pre-flight**: Ubuntu 24.04, ≥2 NIC, ≥1 ГБ `/var`, passwordless sudo, apply-lock свободен.

- `--force` — OS-check → warn
- `--skip-preflight` — пропустить проверки
- lab: `UBROUTER_MIN_NICS=1`, `UBROUTER_MIN_DISK_MB=512`

При `--apply`: snapshot + baseline; healthcheck **90 с** (PPPoE/rename **~180 с**); apply через `systemd-run` (обрыв SSH не убивает процесс); при провале — auto-rollback. Schema validate перед apply.

Секреты (PPPoE/VPN/Telegram) — только в `/etc/ubrouter/answers.local.yaml` (0600), не в git.

## IKEv2 (strongSwan) — мобильные клиенты

Сервер: wizard (фаза VPN) или `vpn.servers` (`type: ikev2`). После apply:

- конфиг: `/etc/swanctl/conf.d/`
- PKI: `/var/lib/ubrouter/pki`
- клиенты: `/root/ubrouter-vpn-clients/`

```bash
sudo ./ubrouter ikev2-client
# или:
sudo ./ubrouter ikev2-client --name anna-android --generate-password --server vpn.example.com
```

| Файл | Назначение |
|------|------------|
| `anna-android.p12` | импорт в приложение |
| `anna-android.pass` | пароль PKCS#12 |
| `anna-android.howto.txt` | инструкция |

На телефоне: **strongSwan VPN Client** → IKEv2 Certificate → `.p12` → Server = публичный IP/FQDN.

Клиент роутера к чужому IKEv2: `vpn.clients` + пароли в `answers.local.yaml`. См. [docs/04-vpn-matrix.md](docs/04-vpn-matrix.md).

## Документация

| Документ | Содержание |
|----------|------------|
| [docs/00-tz.md](docs/00-tz.md) | Техническое задание |
| [docs/01-architecture.md](docs/01-architecture.md) | Архитектура |
| [docs/02-wizard-flow.md](docs/02-wizard-flow.md) | Опросник по фазам (01–13) |
| [docs/03-modules.md](docs/03-modules.md) | Контракт модулей |
| [docs/04-vpn-matrix.md](docs/04-vpn-matrix.md) | Матрица VPN |
| [docs/05-security.md](docs/05-security.md) | Безопасность |
| [docs/06-roadmap.md](docs/06-roadmap.md) | Roadmap |
| [docs/07-audit-followups.md](docs/07-audit-followups.md) | Known issues / закрыто |
| [docs/08-log-tags.md](docs/08-log-tags.md) | Формат логов |
| [docs/09-doctor-export.md](docs/09-doctor-export.md) | doctor / export / import / pre-flight |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Архитектурные решения |
| [tests/acceptance.md](tests/acceptance.md) | Приёмочные сценарии (VM) |

## Что входит в 1.0

- Pre-flight; rename: keep / `ethN` / `etherN`
- Hostname / timezone
- WAN: DHCP / static / PPPoE (+ VLAN/MTU); Multi-WAN **failover** или **LB/ECMP**
- **IPv6** (off / dhcpv6 / slaac) + опциональный LAN ULA + **radvd** RA
- LAN: один порт или bridge; DHCP-теги / static hosts
- NAT + nftables; **port-knock** (WAN SSH); PPPoE → nft WAN=`ppp0`
- dnsmasq, chrony — по согласию; Y→N cleanup
- VPN: WireGuard (+ `wg-peer`), OpenVPN client/**server** (`.ovpn`), GRE / IPIP / EOIP (± **IPsec transport+PSK**), L2TP client (± IPsec), IKEv2 server+client
- Desired-state cleanup: удалили туннель из answers → units/ifaces/conf снимаются (PKI сохраняется)
- IGMP/IPTV, Cake SQM; optional **OSPF** (FRR)
- Hardening: fail2ban, unattended-upgrades
- **Netwatch** + **VPN Telegram notify** (нужен путь к `api.telegram.org`)
- **bypass-policy** (+ полный teardown при `enabled: false`)
- Snapshot / healthcheck / auto-rollback; schema validate; SSH-safe apply
- `doctor` / `export` / `import`

**Не делаем:** Wi‑Fi, Web UI, PPTP, L2TP server, SIP ALG apply, импорт `.rsc`.

## Версия

`VERSION` → **1.0.2**

## Репозиторий

https://github.com/PTah/UBrouter

## Лицензия

MIT — см. `LICENSE`.
