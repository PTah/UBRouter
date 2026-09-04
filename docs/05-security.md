# Безопасность

## Threat model (lite)

| Угроза | Митигация |
|--------|-----------|
| Открытый SSH с WAN | default deny; allowlist; **port-knock** |
| Слабые VPN (PPTP) | отказ в поддержке |
| Утечка секретов в git | `answers.local` + 0600; secrets не в example |
| Поломка сети apply | snapshot + baseline + health 90/180 с + auto-rollback |
| Случайный default route в VPN | wizard confirm |
| «Висящие» туннели после удаления | desired-state cleanup |
| DNS leaks при bypass | dnsmasq на роутере; документировать |

## Права

- apply только root
- пользователь запуска — **passwordless sudo**
- `/etc/ubrouter/answers.yaml` → `0600`/`0640` без секретов
- `answers.local.yaml` — всегда `0600`

```bash
echo 'YOUR_USER ALL=(root) NOPASSWD: ALL' >/etc/sudoers.d/ubrouter
chmod 0440 /etc/sudoers.d/ubrouter
visudo -cf /etc/sudoers.d/ubrouter
```

## Firewall baseline

```text
input:  lo accept; established/related; lan if accept; wan ssh per policy (deny/allowlist/knock); drop
forward: established; lan→wan accept; wan→lan only dnat/related; drop
nat: masquerade oif wan (ppp0 для PPPoE)
```

## Секреты

Не коммитить: bot tokens, PPPoE/VPN passwords, PSK, PKCS#12.  
Только runtime `/etc/ubrouter/answers.local.yaml` и `/root/ubrouter-vpn-clients/`.

## Обновления

unattended-upgrades рекомендуется; security-only по умолчанию.
