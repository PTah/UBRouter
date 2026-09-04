# Контракт модулей

Каталог: `scripts/modules/<module_name>/`.

## Точки входа

| Файл | Exit | Поведение |
|------|------|-----------|
| `plan.sh` | 0/≠0 | Читает `$UBROUTER_ANSWERS`, пишет plan в `$UBROUTER_WORKDIR` |
| `apply.sh` | 0/≠0 | Пакеты, conf, enable/restart; при выключении — cleanup |
| `verify.sh` | 0/≠0 | Проверки (если есть) |

Не у всех модулей есть все три файла — минимум `apply.sh`.

## Окружение

| Переменная | Смысл |
|------------|-------|
| `UBROUTER_ROOT` | корень репо/установки |
| `UBROUTER_ANSWERS` | answers.yaml |
| `UBROUTER_WORKDIR` | workdir plan |
| `UBROUTER_DRY_RUN` | `1` = не менять систему |
| `UBROUTER_HEALTH_WINDOW` | окно healthcheck, сек (default 90) |
| `UBROUTER_ONLY_MODULES` | применить только перечисленные модули |

## Правила

1. Нет интерактивного stdin в apply.
2. Имена интерфейсов — только из answers.
3. Идемпотентность; desired-state cleanup при Y→N / удалении туннеля.
4. Секреты не в world-readable файлах.
5. Лог: stdout кратко; детали `/var/log/ubrouter/<module>.log`.

## Модули apply (1.0)

| Модуль | Назначение |
|--------|------------|
| `interfaces` | rename / map |
| `wan` | DHCP/static/PPPoE (+IPv6) |
| `lan` | адресация, bridge, radvd |
| `multi-wan` | failover / LB watch |
| `nat-firewall` | nft NAT/fw, knock, forwards |
| `dns-dhcp` | dnsmasq (+ tags/hosts) |
| `ntp` | chrony |
| `vpn` | dispatcher → type-подмодули |
| `bypass-policy` | selective routing |
| `igmpproxy` | IPTV multicast |
| `qos` | Cake SQM |
| `hardening` | fail2ban, UU |
| `monitoring` | netwatch, vpn-watch, Telegram |
| `ospf` | FRR |

### VPN type-подмодули

`wireguard`, `openvpn`, `gre`, `ipip`, `l2tp`, `ikev2`, `eoip`, `tunnel-ipsec`  
Helpers: `scripts/lib/vpn-cleanup.sh`.

### Stub / out of product

- `optional/sip-alg` — wizard может записать флаг; **apply не настраивает** SIP ALG.
- L2TP **server**, Wi‑Fi, Web UI, PPTP — не реализуются.
