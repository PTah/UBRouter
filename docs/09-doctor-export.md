# doctor / export / import — диагностический CLI и миграция

Актуально для **1.0.x** (добавлено с 0.4.8).

## `ubrouter doctor`

Диагностика всех модулей + reachability + snapshot integrity. Не пишет ничего на диск, только читает и проверяет.

```bash
sudo ubrouter doctor
```

Что проверяет (по секциям):

| Секция | Что |
|--------|-----|
| state | `/etc/ubrouter/state.json`, `answers.yaml` |
| kernel | `net.ipv4.ip_forward`, sysctl drop-in |
| interfaces | все имена из `interfaces.map` существуют |
| wan | default route присутствует |
| dns | dnsmasq active, DHCP leases count, upstream DNS (dig @1.1.1.1), локальный DNS (dig @127.0.0.1) |
| ntp | chrony active, chronyc sources |
| firewall | nftables active, forward chain, bypass nft table |
| vpn | wg-интерфейсы, `wg show`, GRE/IPIP/tun, strongSwan + `swanctl --list-sas` |
| bypass | `ip rule fwmark`, `ip route show table N` |
| multi-wan | `/etc/ubrouter/multiwan.conf`, `multiwan.active`, default routes |
| snapshots | count, latest, MANIFEST integrity (каждый path в snapshot существует) |
| lock | apply lock свободен |
| units | список `ubrouter-*` + dnsmasq/chrony/nftables с active/enabled |

Выход:
- `OK=N  WARN=M  CRIT=K`
- exit 0 если `CRIT=0`, иначе exit 1

Использование в monitoring (cron / NRPE / check_mk):

```bash
# /etc/cron.daily/ubrouter-doctor
#!/bin/sh
/usr/local/sbin/ubrouter doctor >/var/log/ubrouter/doctor.log 2>&1 || \
  logger -t ubrouter "doctor: CRIT failures — см. /var/log/ubrouter/doctor.log"
```

## `ubrouter export`

Бэкап состояния в tar.gz. **Содержит приватные ключи и пароли** — chmod 0600, в сейф.

```bash
sudo ubrouter export
# → /root/ubrouter-backup-20260812T153000.tar.gz

sudo ubrouter export --out /mnt/usb/ub-backup.tar.gz
sudo ubrouter export --no-pki         # skip /var/lib/ubrouter/pki (CA key)
sudo ubrouter export --no-secrets     # skip answers.local.yaml
sudo ubrouter export --include-logs   # + /var/log/ubrouter
```

Что попадает в tarball:
- `/etc/ubrouter/` (answers.yaml, state.json, bypass.env, multiwan.conf, answers.local.yaml — если не `--no-secrets`)
- `/var/lib/ubrouter/pki/` (CA key, server cert, client certs) — если не `--no-pki`
- `/root/ubrouter-vpn-clients/` (.p12 + .pass для IKEv2 клиентов)
- `/etc/wireguard/` (private keys!)
- `/etc/openvpn/` (client configs)
- `/etc/swanctl/` (IKEv2 configs + certs)
- `/etc/xl2tpd/` (L2TP)
- `/etc/ppp/` (ubrouter-wan peer, pap/chap-secrets)
- `/etc/netplan/50-ubrouter.yaml`, `/etc/netplan/60-ubrouter-multiwan.yaml`
- `/etc/nftables.conf`, `/etc/dnsmasq.conf`, `/etc/dnsmasq.d/`, `/etc/chrony/`, `/etc/sysctl.d/99-ubrouter.conf`
- `/etc/fail2ban/jail.d/`
- `/etc/systemd/resolved.conf.d/ubrouter.conf`, `/etc/systemd/system/dnsmasq.service.d/`
- `/etc/cloud/cloud.cfg.d/99-ubrouter-disable-network.cfg`
- `/etc/systemd/system/ubrouter-*.service` + `ubrouter-*.timer` + `swanctl-load.service`
- `/usr/local/lib/ubrouter/` (helper scripts)
- `/usr/local/sbin/ubrouter-swanctl-load.sh`
- `META.json` (version, hostname, kernel, OS)
- `MANIFEST.txt` (список путей)

## `ubrouter import`

Восстановление из tarball. **Делает pre-import snapshot** автоматически — можно `ubrouter rollback` если что-то пошло не так.

```bash
sudo ubrouter import /mnt/usb/ub-backup.tar.gz
# спросит подтверждение

sudo ubrouter import /mnt/usb/ub-backup.tar.gz --yes
# без вопросов
```

После import:
- `systemctl daemon-reload`
- `sysctl --system`
- `netplan generate` (без apply)

Дальше — пользователь решает:
```bash
sudo ubrouter status      # проверить
sudo ubrouter doctor      # диагностика
sudo ubrouter apply       # если нужно пересобрать юниты/конфиги
```

Для rename интерфейсов может понадобиться reboot (как и после обычного apply с rename).

## Pre-flight checks в `install.sh`

Перед wizard/apply теперь прогоняются проверки:

| Проверка | Критичность | --force лечит? |
|----------|-------------|----------------|
| OS = Ubuntu 24.04 | error → warn с `--force` | да |
| ≥2 физических NIC | error | нет (override: `UBROUTER_MIN_NICS=1`) |
| ≥1 ГБ free на `/var` | error | нет (override: `UBROUTER_MIN_DISK_MB=512`) |
| root или passwordless sudo | error | нет |
| python3 + python3-yaml | error / warn | нет |
| netplan | warn | — |
| apply lock не занят | error | нет |

```bash
sudo ./install.sh                          # с preflight
sudo ./install.sh --force                  # OS check → warn
sudo ./install.sh --skip-preflight         # без проверок (опасно)
UBROUTER_MIN_NICS=1 sudo ./install.sh      # для Single-NIC lab
```

## Типичные сценарии

### Переезд на новое железо

```bash
# на старом роутере:
sudo ubrouter export --out /mnt/usb/backup.tar.gz

# на новом (чистая Ubuntu 24.04):
git clone https://github.com/PTah/UBrouter.git
cd UBrouter
sudo ./install.sh                          # wizard заполняет answers под новое железо (MAC map)
                                            # НО не apply!
sudo cp /mnt/usb/backup.tar.gz /tmp/
sudo ubrouter import /tmp/backup.tar.gz --yes
sudo ubrouter doctor
# если interfaces.map не совпал по MAC — поправить в /etc/ubrouter/answers.yaml вручную
sudo ubrouter apply
```

### Регулярный бэкап (cron)

```bash
# /etc/cron.weekly/ubrouter-backup
#!/bin/sh
/usr/local/sbin/ubrouter export --out /var/backups/ubrouter-$(date -u +%Y%m%d).tar.gz
find /var/backups -name 'ubrouter-*.tar.gz' -mtime +30 -delete
```

### Monitoring

```bash
# /etc/cron.daily/ubrouter-doctor
#!/bin/sh
/usr/local/sbin/ubrouter doctor >/var/log/ubrouter/doctor.log 2>&1 || \
  mail -s "UBrouter doctor: FAIL on $(hostname)" admin@example.com </var/log/ubrouter/doctor.log
```
