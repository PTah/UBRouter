# Module: multi-wan

Status: **0.6.0**

Вторичные WAN в `wan.multi` + политика `wan.multi_mode`:

| Mode | Поведение |
|------|-----------|
| `failover` (default) | один живой default metric 10; остальные demote |
| `lb` | ECMP (`nexthop … weight 1`) на всех живых WAN |

Probe: timer `ubrouter-multiwan-watch` → `ping -I <iface> 1.1.1.1`.

```yaml
wan:
  interface: eth0
  mode: dhcp
  multi_mode: lb          # failover | lb
  multi:
    - { interface: eth2, mode: dhcp, metric: 200 }
```

Проверка: `cat /etc/ubrouter/multiwan.mode`, `ip route show default`, `journalctl -t ubrouter-multiwan -e`.
