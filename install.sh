#!/usr/bin/env bash
# ==========================================================
# DNS ANYCAST INSTALLER (UNBOUND + FRR + HYPERLOCAL)
# BY: LAILSON ARAUJO | +55 83 98615-2503
# ==========================================================

# CONFIGURAÇÃO DE CORES "HACKER" COM CONTRASTE NOS BOTÕES
export NEWT_COLORS='
  root=white,black
  window=white,black
  border=green,black
  shadow=white,black
  button=green,black
  actbutton=black,white
  compactbutton=green,black
  title=green,black
  textbox=green,black
  acttextbox=black,white
  entry=green,black
  disentry=gray,black
  checkbox=green,black
  actcheckbox=black,white
  listbox=green,black
  actlistbox=black,white
'

set -euo pipefail

NAME="LAILSON ARAUJO"
PHONE="+55 83 98615-2503"
BTITLE="[ DNS ANYCAST SYSTEM ] - $NAME | $PHONE"

# ---------- Funções Auxiliares ----------

require_deps() {
  apt-get update && apt-get install -y whiptail sipcalc frr unbound zabbix-sender dnsutils curl
}

draw_progress() {
  ( echo 25 ; sleep 0.3 ; echo 50 ; sleep 0.3 ; echo 75 ; sleep 0.3 ; echo 100 ) | \
  whiptail --backtitle "$BTITLE" --title " PROCESSANDO " --gauge "$1" 8 70 0
}

# ---------- Coleta de Parâmetros com Botão Voltar ----------

collect_params() {
  STEP=1
  while true; do
    case $STEP in
      1)
        HOSTNAME_NEW=$(whiptail --backtitle "$BTITLE" --title " [ 01 - HOSTNAME ] " --inputbox "Nome do servidor:" 10 70 "$(hostname)" 3>&1 1>&2 2>&3) || exit 1
        hostnamectl set-hostname "$HOSTNAME_NEW"
        STEP=2
        ;;
      2)
        WAN_IF=$(whiptail --backtitle "$BTITLE" --title " [ 02 - INTERFACE ] " --inputbox "Interface WAN (Ex: ens18):" 10 70 "ens18" 3>&1 1>&2 2>&3) || STEP=1
        [[ $? -eq 0 ]] && STEP=3
        ;;
      3)
        IPV4_CIDR=$(whiptail --backtitle "$BTITLE" --title " [ 03 - IPV4/CIDR ] " --inputbox "IPv4 Público (Ex: 198.18.1.2/30):" 10 70 "198.18.1.2/30" 3>&1 1>&2 2>&3) || STEP=2
        if [ $? -eq 0 ]; then
          SUGGESTED_GW=$(sipcalc "$IPV4_CIDR" | grep "Usable range" | awk '{print $4}' || echo "")
          STEP=4
        fi
        ;;
      4)
        IPV4_GW=$(whiptail --backtitle "$BTITLE" --title " [ 04 - GATEWAY V4 ] " --inputbox "Confirme o Gateway IPv4:" 10 70 "$SUGGESTED_GW" 3>&1 1>&2 2>&3) || STEP=3
        [[ $? -eq 0 ]] && STEP=5
        ;;
      5)
        IPV6_PUB=$(whiptail --backtitle "$BTITLE" --title " [ 05 - IPV6/CIDR ] " --inputbox "IPv6 Público (Ex: 2804:bebe:cafe::2/64):" 10 70 "2804:bebe:cafe::2/64" 3>&1 1>&2 2>&3) || STEP=4
        if [ $? -eq 0 ]; then
          SUGGESTED_V6_GW=$(echo "$IPV6_PUB" | cut -d/ -f1 | sed 's/[0-9a-fA-F]*$/1/')
          STEP=6
        fi
        ;;
      6)
        IPV6_GW=$(whiptail --backtitle "$BTITLE" --title " [ 06 - GATEWAY V6 ] " --inputbox "Confirme o Gateway IPv6:" 10 70 "$SUGGESTED_V6_GW" 3>&1 1>&2 2>&3) || STEP=5
        [[ $? -eq 0 ]] && STEP=7
        ;;
      7)
        LB_DATA=$(whiptail --backtitle "$BTITLE" --title " [ 07 - ANYCAST IPs ] " --inputbox "V4_1,V4_2,V6_1,V6_2:" 10 70 "10.10.10.10,10.10.9.9,fd00::10:10:10:10,fd00::10:10:9:9" 3>&1 1>&2 2>&3) || STEP=6
        if [ $? -eq 0 ]; then
          IFS=',' read -r L1V4 L2V4 L1V6 L2V6 <<< "$LB_DATA"
          STEP=8
        fi
        ;;
      8)
        ACL_DATA=$(whiptail --backtitle "$BTITLE" --title " [ 08 - ACLs ] " --inputbox "Prefixos V4,V6 (Ex: 192.168.0.0/16,2001:db8::/32):" 10 70 "198.18.0.0/22,2001:db8::/32" 3>&1 1>&2 2>&3) || STEP=7
        if [ $? -eq 0 ]; then
          IFS=',' read -r ACL_V4 ACL_V6 <<< "$ACL_DATA"
          STEP=9
        fi
        ;;
      9)
        SUMMARY="CONFIRME OS DADOS:
        Hostname: $HOSTNAME_NEW | WAN: $WAN_IF
        IPv4: $IPV4_CIDR (GW: $IPV4_GW)
        IPv6: $IPV6_PUB (GW: $IPV6_GW)
        Anycast V4: $L1V4, $L2V4
        Anycast V6: $L1V6, $L2V6
        ACLs: $ACL_V4 | $ACL_V6"
        whiptail --backtitle "$BTITLE" --title " [ 09 - FINALIZAR ] " --yesno "$SUMMARY" 18 78 && break || STEP=8
        ;;
    esac
  done
}

# ---------- Funções de Escrita de Arquivos ----------

apply_configs() {
  # 1. Network
  cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
auto lo:0
iface lo:0 inet static
      address $L1V4/32
auto lo:1
iface lo:1 inet static
      address $L2V4/32
auto lo:2
iface lo:2 inet6 static
      address $L1V6/128
auto lo:3
iface lo:3 inet6 static
      address $L2V6/128

auto $WAN_IF
iface $WAN_IF inet static
      address $IPV4_CIDR
      gateway $IPV4_GW
iface $WAN_IF inet6 static
      pre-up modprobe ipv6
      address $IPV6_PUB
      gateway $IPV6_GW
EOF

  # 2. FRR Template
  RID=$(echo "$IPV4_CIDR" | cut -d/ -f1)
  sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
  sed -i 's/ospf6d=no/ospf6d=yes/' /etc/frr/daemons
  cat > /etc/frr/frr.conf <<EOF
frr version 10.3
frr defaults traditional
hostname $HOSTNAME_NEW
service integrated-vtysh-config
!
interface $WAN_IF
 ip ospf area 0.0.0.0
 ip ospf network point-to-point
 ipv6 ospf6 area 0.0.0.0
 ipv6 ospf6 network point-to-point
!
interface lo
 ip ospf area 0.0.0.0
 ip ospf passive
 ipv6 ospf6 area 0.0.0.0
 ipv6 ospf6 passive
!
router ospf
 ospf router-id $RID
!
router ospf6
 ospf6 router-id $RID
 redistribute connected
EOF

  # 3. Reiniciar serviços
  systemctl restart networking
  systemctl restart frr
}

# ---------- MAIN ----------

main() {
  clear
  require_deps
  collect_params
  draw_progress "Aplicando configurações de rede e OSPF..."
  apply_configs
  whiptail --backtitle "$BTITLE" --title " INSTALAÇÃO CONCLUÍDA " --msgbox "O sistema foi configurado.\n\nAutor: $NAME" 10 60
  clear
}

main "$@"
