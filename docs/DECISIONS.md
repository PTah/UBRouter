# Зафиксированные продуктовые решения

1. **Wizard → answers.yaml → modular apply** — основной UX (фазы 01–13).
2. **Имена интерфейсов** — keep / eth / ether / custom.
3. **WAN + LAN L3**; LAN bridge; **Multi-WAN** `failover` | `lb`.
4. **WAN:** DHCP / static / PPPoE (+ VLAN); **IPv6** off/dhcpv6/slaac + LAN ULA/RA.
5. **Службы по согласию:** dnsmasq (+DHCP-теги), chrony, NAT, firewall, fail2ban, SQM, IGMP/IPTV, Netwatch (+Telegram).
6. **VPN shipped:** WG, OpenVPN (client+server), GRE/IPIP/EOIP (± IPsec), L2TP client (± IPsec), IKEv2 (server+client). **PPTP wont.** L2TP server — не делаем.
7. **bypass-policy** в том же wizard+apply; `ubrouter bypass`.
8. **Wont:** Wi‑Fi, Web UI, PPTP, импорт `.rsc` как ядро.
9. **Стек:** Ubuntu 24.04, netplan+networkd, nftables, dnsmasq, chrony.
10. **Apply safety:** snapshot + baseline + health **90/180 с** + auto-rollback; SSH-safe (`systemd-run`); schema validate.
11. **Passwordless sudo** для пользователя запуска.
12. **Remotes:** эталон — приватный Gitea (`home`); публичный GitHub — только orphan + sanitize (без внутренней истории и IDE-артефактов).
13. **Port-knock** опционально (`firewall.wan_ssh: knock`).
14. **VPN Telegram notify** — IKEv2 updown + iface watch.
15. **OSPF** — optional FRR (фаза 12).
16. **Desired-state cleanup** — удаление туннеля / Y→N снимает runtime; PKI сохраняется.
17. **SIP ALG:** флаг в wizard возможен; apply stub (руками при необходимости).
