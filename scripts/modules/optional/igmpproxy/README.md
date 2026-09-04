# optional/igmpproxy

IGMP/IPTV multicast proxy (`igmpproxy`) для раздачи IPTV с WAN на LAN.

## Answers

```yaml
igmpproxy:
  enabled: true
  upstream: eth0      # ISP / WAN
  downstream: br-lan  # LAN
  quickleave: true
  altnet: null        # optional CIDR
services:
  igmpproxy: true     # зеркало флага для оркестратора
```

Wizard: фаза `10-igmp-iptv`.

## Apply (TODO 0.3.0)

1. Пакет `igmpproxy`
2. `/etc/igmpproxy.conf` из answers
3. nft: разрешить IGMP / multicast forward WAN↔LAN
4. enable `igmpproxy.service`
