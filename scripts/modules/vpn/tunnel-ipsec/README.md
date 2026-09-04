# tunnel-ipsec

IPsec **transport** + PSK для GRE / EOIP / IPIP (стиль MikroTik `ipsec-secret`).

```yaml
vpn:
  clients:
    - type: gre
      name: gre0
      remote: 203.0.113.2
      local: auto
      ipsec: true          # false = чистый туннель
```

PSK только в `answers.local.yaml`:

```yaml
vpn:
  tunnel_psks:
    gre0: "shared-secret"
```

Wizard спрашивает: чистый туннель или с IPsec.
