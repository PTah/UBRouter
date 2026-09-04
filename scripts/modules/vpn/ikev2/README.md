# Module: vpn/ikev2 (strongSwan)

Status: **0.4.1**

## Сервер (`vpn.servers[]`, type: ikev2)

- PKI: `/var/lib/ubrouter/pki`
- swanctl drop-in: `/etc/swanctl/conf.d/ubrouter-<name>.conf`
- PKCS#12 клиенты: `/root/ubrouter-vpn-clients/*.p12` (+ `*.pass`, `*.howto.txt`)
- UDP 500/4500 в nft (best-effort)
- `ubrouter-swanctl-load.service` после `strongswan-starter`

```yaml
vpn:
  servers:
    - type: ikev2
      name: ikev2-server
      id: auto              # или FQDN / публичный IP
      server_cn: ubrouter-vpn
      pool: 10.67.0.10-10.67.0.200
      dns: ["10.0.0.1"]
      local_ts: 0.0.0.0/0   # или только LAN CIDR
      clients: [phone]      # первичные — через apply → issue-client.sh
```

### Новый клиент (PKCS#12) — отдельный скрипт

После того как сервер уже поднят:

```bash
sudo ./ubrouter ikev2-client
# или:
sudo ./ubrouter ikev2-client --name anna-android --generate-password
sudo ./ubrouter ikev2-client --name laptop-bob --password '...' --server vpn.example.com
```

Скрипт: `scripts/modules/vpn/ikev2/issue-client.sh`  
Спросит имя, пароль (или сгенерирует), SAN, адрес сервера.  
Результат в `/root/ubrouter-vpn-clients/`:

| Файл | Назначение |
|------|------------|
| `anna-android.p12` | импорт в strongSwan VPN Client |
| `anna-android.pass` | пароль PKCS#12 |
| `anna-android.howto.txt` | краткая инструкция |

Android: **strongSwan VPN Client** → IKEv2 Certificate → импорт `.p12` → Server = публичный IP/FQDN.

## Клиент роутера (`vpn.clients[]`, type: ikev2)

```yaml
vpn:
  clients:
    - type: ikev2
      name: to-office
      remote: vpn.example.com
      auth: eap-mschapv2    # eap-mschapv2 | psk | pubkey
      eap_id: user@example
      remote_ts: 10.0.0.0/8
      auto_start: true
```

Пароль/PSK — в `/etc/ubrouter/answers.local.yaml`:

```yaml
vpn:
  ikev2_passwords:
    to-office: "secret"
  ikev2_psks:
    other: "psk-secret"
```
