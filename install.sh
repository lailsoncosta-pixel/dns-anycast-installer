#!/usr/bin/env bash
# ==========================================================
# DNS ANYCAST INSTALLER (UNBOUND + FRR + HYPERLOCAL)
# Automação completa com interface WHIPTAIL (TUI)
# BY: LAILSON ARAUJO
# ==========================================================

set -euo pipefail

# ---------- Funções auxiliares ----------

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
  fi
}

require_debian_12() {
  if ! grep -q "VERSION_CODENAME=bookworm" /etc/os-release 2>/dev/null; then
    echo "ATENÇÃO: este instalador foi pensado para Debian 12 (bookworm)."
    sleep 3
  fi
}

require_whiptail() {
  if ! command -v whiptail &>/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail
  fi
}

ask_input() {
  local title="$1"
  local text="$2"
  local default="${3:-}"
  local result
  result=$(whiptail --title "$title" --inputbox "$text" 0 0 "$default" 3>&1 1>&2 2>&3) || {
    echo "Cancelado."
    exit 1
  }
  echo "$result"
}

ask_yesno() {
  local title="$1"
  local text="$2"
  if whiptail --title "$title" --yesno "$text" 0 0; then
    return 0
  else
    return 1
  fi
}

# ---------- Coleta de parâmetros ----------

collect_params() {
  whiptail --title "DNS Anycast Installer - BY LAILSON ARAUJO" \
    --msgbox "Bem-vindo ao instalador automatizado do DNS Recursivo Anycast.\n\nPressione OK para começar." 0 0

  HOSTNAME_NEW=$(ask_input "Hostname" "Informe o hostname do servidor (ex: dns-01):" "$(hostname)")
  hostnamectl set-hostname "$HOSTNAME_NEW"

  WAN_IF=$(ask_input "Interface WAN" "Informe a interface principal (WAN):" "ens18")

  IPV4_PUB=$(ask_input "IPv4 Público" "IPv4 para recursividade e Router-ID:" "198.18.1.10")
  IPV4_PUB_CIDR=$(ask_input "Máscara IPv4" "Máscara CIDR (ex: 27):" "27")
  IPV4_GW=$(ask_input "Gateway IPv4" "Gateway da rede IPv4:" "198.18.1.1")

  IPV6_PUB=$(ask_input "IPv6 Público" "Informe o IPv6 completo (ex: 2804:bebe:cafe::2/64):" "2804:bebe:cafe::2/64")
  IPV6_GW=$(ask_input "Gateway IPv6" "Informe o Gateway IPv6:" "2804:bebe:cafe::1")

  LOOPBACK1_V4=$(ask_input "Anycast IP 1" "IPv4 Anycast 1:" "10.10.10.10")
  LOOPBACK2_V4=$(ask_input "Anycast IP 2" "IPv4 Anycast 2:" "10.10.9.9")
  LOOPBACK1_V6=$(ask_input "Anycast IPv6 1" "IPv6 Anycast 1:" "fd00::10:10:10:10")
  LOOPBACK2_V6=$(ask_input "Anycast IPv6 2" "IPv6 Anycast 2:" "fd00::10:10:9:9")

  LINK_V4=$(ask_input "IP Link /30" "Seu IPv4 na ponta do link /30 com o PE:" "172.16.0.6")
  LINK_V4_CIDR=$(ask_input "CIDR Link" "CIDR (ex: 30):" "30")

  ACL_V4=$(ask_input "ACL IPv4" "Prefixos IPv4 autorizados (vírgula):" "198.18.0.0/22")
  ACL_V6=$(ask_input "ACL IPv6" "Prefixos IPv6 autorizados (vírgula):" "2001:db8::/32")

  # Zabbix / DoH / Telegram (mantidos conforme original)
  ENABLE_ZABBIX=$(ask_yesno "Zabbix" "Habilitar métricas para Zabbix?" && echo 1 || echo 0)
  if [[ $ENABLE_ZABBIX -eq 1 ]]; then
      ZABBIX_IP=$(ask_input "Zabbix Server" "IP do Servidor Zabbix:" "192.168.10.1")
      ZABBIX_HOSTNAME=$(ask_input "Host Zabbix" "Nome do host no Zabbix:" "$HOSTNAME_NEW")
  fi

  ENABLE_DOH=$(ask_yesno "DoH" "Habilitar DNS over HTTPS?" && echo 1 || echo 0)
  [[ $ENABLE_DOH -eq 1 ]] && DOH_DOMAIN=$(ask_input "Domínio DoH" "FQDN para o DoH:" "doh.exemplo.com")

  ENABLE_TELEGRAM=$(ask_yesno "Telegram" "Preparar script para alertas via Telegram?" && echo 1 || echo 0)
}

# ---------- Configurações de Sistema ----------

configure_network_interfaces() {
  cat > /etc/network/interfaces <<EOF
# Gerado por DNS Anycast Installer - Lailson Araujo
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto lo:0
iface lo:0 inet static
      address $LOOPBACK1_V4/32

auto lo:1
iface lo:1 inet static
      address $LOOPBACK2_V4/32

auto lo:2
iface lo:2 inet6 static
      address $LOOPBACK1_V6/128

auto lo:3
iface lo:3 inet6 static
      address $LOOPBACK2_V6/128

auto $WAN_IF
iface $WAN_IF inet static
      address $IPV4_PUB/$IPV4_PUB_CIDR
      gateway $IPV4_GW

iface $WAN_IF inet6 static
      pre-up modprobe ipv6
      address $IPV6_PUB
      gateway $IPV6_GW

auto ${WAN_IF}:0
iface ${WAN_IF}:0 inet static
      address $LINK_V4/$LINK_V4_CIDR
EOF
  systemctl restart networking || true
}

configure_frr() {
  # Ativa os daemons necessários
  sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
  sed -i 's/ospf6d=no/ospf6d=yes/' /etc/frr/daemons

  # Cria o arquivo de configuração baseado no seu template
  cat > /etc/frr/frr.conf <<EOF
!
frr version 10.3
frr defaults traditional
hostname $HOSTNAME_NEW
log syslog informational
no ip forwarding
no ipv6 forwarding
service integrated-vtysh-config
!
interface $WAN_IF
 ip ospf area 0.0.0.0
 ip ospf network point-to-point
 ipv6 ospf6 area 0.0.0.0
 ipv6 ospf6 network point-to-point
exit
!
interface lo
 description LOOPBACKS
 ip ospf area 0.0.0.0
 ip ospf passive
 ipv6 ospf6 area 0.0.0.0
 ipv6 ospf6 passive
exit
!
router ospf
 ospf router-id $IPV4_PUB
exit
!
router ospf6
 ospf6 router-id $IPV4_PUB
 redistribute connected
exit
!
end
EOF
  chown frr:frr /etc/frr/frr.conf /etc/frr/daemons
  systemctl restart frr
}

# (Demais funções como tune_sysctl, configure_unbound, etc permanecem as mesmas do seu original)
# [ ... Inclua aqui as funções de tuning, unbound e scripts que você já escreveu ... ]

# ---------- MAIN Corrigido ----------

main() {
  require_root
  require_debian_12
  require_whiptail
  collect_params
  
  # Execução das etapas
  # configure_apt_sources
  # install_base_packages
  # tune_sysctl_nf_conntrack
  configure_network_interfaces
  # disable_thp
  # configure_chrony
  # configure_unbound_logrotate
  # configure_unbound
  configure_frr # Nova função integrada
  # configure_resolvconf
  # install_unbound_zabbix_sender_script
  # install_checa_dns_script

  whiptail --title "Concluído" --msgbox "Instalação concluída!\nFRR e Interfaces configurados.\n\nBY: LAILSON ARAUJO" 0 0
}

main "$@"
