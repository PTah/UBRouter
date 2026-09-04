# Module: ospf (optional)

FRR OSPFv2 для желающих. Wizard фаза `12-ospf`.

```yaml
routing:
  ospf:
    enabled: true
    router_id: 10.0.0.1
    redistribute_connected: true
    passive_interfaces: [eth0]
    networks:
      - { prefix: "10.0.0.1/24", area: "0.0.0.0" }
```
