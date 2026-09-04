#!/usr/bin/env bash
# Фаза 07 — VPN clients/servers (WG / OpenVPN / IKEv2 + туннели ± IPsec)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

vpn_clients="[]"
vpn_servers="[]"

ask_tunnel_ipsec() {
  # sets globals: ipsec_yaml (true/false), prints warn about PSK
  local name="$1"
  echo
  echo "Туннель «$name»:"
  echo "  1) чистый (без шифрования поверх)"
  echo "  2) с IPsec (transport + PSK, как MikroTik ipsec-secret)"
  local c
  c="$(ask "Выбор" "1")"
  if [[ "$c" == "2" ]]; then
    ipsec_yaml=true
    warn "PSK: /etc/ubrouter/answers.local.yaml → vpn.tunnel_psks.$name"
  else
    ipsec_yaml=false
  fi
}

if confirm "Настроить VPN-клиент / туннель?" N; then
  echo "Типы: wireguard | openvpn | gre | ipip | l2tp | ikev2 | eoip"
  echo "PPTP не поддерживается."
  typ="$(ask "Тип первого клиента (или skip)" "skip")"
  if [[ "$typ" == "pptp" ]]; then
    warn "PPTP отклонён политикой безопасности UBrouter"
  elif [[ "$typ" != "skip" ]]; then
    name="$(ask "Имя" "${typ}0")"
    if [[ "$typ" == "ikev2" ]]; then
      remote="$(ask "Удалённый сервер (FQDN/IP)" "")"
      auth="$(ask "auth: eap-mschapv2 | psk | pubkey" "eap-mschapv2")"
      eap_id="$(ask "EAP id / локальный id" "$name")"
      vpn_clients="[{type: ikev2, name: $name, remote: \"$remote\", auth: $auth, eap_id: \"$eap_id\", auto_start: true}]"
      warn "пароль/PSK: /etc/ubrouter/answers.local.yaml → vpn.ikev2_passwords.$name"
    elif [[ "$typ" == "wireguard" || "$typ" == "openvpn" ]]; then
      cfg="$(ask "Путь к config_file" "/etc/ubrouter/import/${name}.conf")"
      vpn_clients="[{type: $typ, name: $name, config_file: \"$cfg\"}]"
    elif [[ "$typ" == "gre" || "$typ" == "ipip" || "$typ" == "eoip" ]]; then
      rem="$(ask "Remote IP" "")"
      loc="$(ask "Local (auto или IP)" "auto")"
      mtu_def=1436
      [[ "$typ" == "ipip" ]] && mtu_def=1480
      [[ "$typ" == "eoip" ]] && mtu_def=1476
      mtu="$(ask "MTU" "$mtu_def")"
      ipsec_yaml=false
      ask_tunnel_ipsec "$name"
      extra=""
      if [[ "$typ" == "eoip" ]]; then
        tid="$(ask "EOIP tunnel_id (GRE key)" "10")"
        extra=", tunnel_id: $tid"
      elif [[ "$typ" == "gre" ]]; then
        gkey="$(ask "GRE key (пусто=нет)" "")"
        [[ -n "$gkey" ]] && extra=", key: $gkey"
      fi
      addr="$(ask "Адрес на туннеле CIDR (пусто=нет)" "")"
      addr_yaml=""
      [[ -n "$addr" ]] && addr_yaml=", address: \"$addr\""
      vpn_clients="[{type: $typ, name: $name, remote: \"$rem\", local: \"$loc\", mtu: $mtu, ipsec: $ipsec_yaml${extra}${addr_yaml}}]"
    elif [[ "$typ" == "l2tp" ]]; then
      rem="$(ask "L2TP server" "")"
      user="$(ask "L2TP username" "")"
      echo
      echo "L2TP IPsec:"
      echo "  1) без IPsec  2) с IPsec PSK"
      lc="$(ask "Выбор" "2")"
      if [[ "$lc" == "2" ]]; then
        vpn_clients="[{type: l2tp, name: $name, server: \"$rem\", user: \"$user\", ipsec: true}]"
        warn "пароли: answers.local → vpn.l2tp_passwords.$name и vpn.l2tp_psks.$name"
      else
        vpn_clients="[{type: l2tp, name: $name, server: \"$rem\", user: \"$user\", ipsec: false}]"
        warn "пароль: answers.local → vpn.l2tp_passwords.$name"
      fi
    else
      vpn_clients="[{type: $typ, name: $name}]"
      info "детали $typ — допишите в answers.yaml"
    fi
  fi
fi

if confirm "Настроить VPN-сервер?" N; then
  echo "  1) WireGuard"
  echo "  2) OpenVPN server (+ .ovpn клиентам)"
  echo "  3) IKEv2 / strongSwan (+ PKCS#12 клиентам)"
  echo "  4) skip"
  c="$(ask "Выбор" "4")"
  case "$c" in
    1)
      listen="$(ask "WG listen UDP" "51820")"
      addr="$(ask "Адрес интерфейса сервера" "10.66.0.1/24")"
      vpn_servers="[{type: wireguard, name: wg-server, listen: $listen, address: \"$addr\", peers: []}]"
      info "peers: sudo ./ubrouter wg-peer --server wg-server --name phone"
      ;;
    2)
      listen="$(ask "OpenVPN listen port" "1194")"
      proto="$(ask "proto udp|tcp" "udp")"
      net="$(ask "Клиентская сеть (CIDR)" "10.8.0.0/24")"
      pub="$(ask "Публичный IP/FQDN для .ovpn (auto=определить)" "auto")"
      users="$(ask "Имена клиентов через пробел (.ovpn)" "phone")"
      ulist="$(python3 -c 'import sys; print("[" + ", ".join(chr(34)+u+chr(34) for u in sys.argv[1:] if u) + "]")' $users)"
      vpn_servers="[{type: openvpn, name: ovpn-server, listen: $listen, proto: $proto, network: \"$net\", public_host: \"$pub\", clients: $ulist}]"
      info "после apply: /root/ubrouter-vpn-clients/*.ovpn"
      ;;
    3)
      sid="$(ask "Server id (auto=WAN IP или FQDN)" "auto")"
      users="$(ask "Имена клиентов через пробел (PKCS#12)" "phone")"
      ulist="$(python3 -c 'import sys; print("[" + ", ".join(chr(34)+u+chr(34) for u in sys.argv[1:] if u) + "]")' $users)"
      vpn_servers="[{type: ikev2, name: ikev2-server, id: \"$sid\", pool: \"10.67.0.10-10.67.0.200\", clients: $ulist}]"
      info "после apply: /root/ubrouter-vpn-clients/*.p12"
      ;;
    *) vpn_servers="[]" ;;
  esac
fi

cat >"$TMP/vpn.yaml" <<EOF
vpn_clients: $vpn_clients
vpn_servers: $vpn_servers
EOF
