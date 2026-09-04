# Module: bypass-policy

Status: **0.4.0**

Selective routing без встроенных списков:

1. Пользователь кладёт CIDR/domain файлы в `/etc/ubrouter/bypass/`
2. `nft` set `inet ubrouter_bypass bypass_dst` + mark (`bypass.fwmark`)
3. `ip rule fwmark → table` + `default dev bypass.target`
4. dnsmasq `nftset=` для доменов
5. Timer: fail-open при падении туннеля

```yaml
bypass:
  enabled: true
  domain_files: [/etc/ubrouter/bypass/domains]
  cidr_files: [/etc/ubrouter/bypass/cidrs]
  target: gre0
  table: 200
  fwmark: "0x2"
  fail_open: true
  mark_lan_only: true
```

Точечно: `sudo ./ubrouter bypass`
