#!/usr/bin/env bash
# ==========================================================
# DNS ANYCAST INSTALLER (UNBOUND + FRR + HYPERLOCAL)
# BY: LAILSON ARAUJO | +55 83 98615-2503
# Alvo: Debian 12 (Bookworm)
# ==========================================================

# CONFIGURAÇÃO DE CORES (Tema Azul Original com Alto Contraste)
export NEWT_COLORS='
  root=,blue
  window=,lightgray
  border=blue,lightgray
  shadow=,black
  button=white,blue
  actbutton=white,cyan
  compactbutton=white,blue
  title=blue,lightgray
  textbox=blue,lightgray
  acttextbox=white,blue
  entry=black,lightcyan
  disentry=gray,lightgray
  checkbox=black,lightcyan
  actcheckbox=white,cyan
  listbox=black,lightcyan
  actlistbox=white,cyan
'

set -euo pipefail

NAME="LAILSON ARAUJO"
PHONE="+55 83 98615-2503"
BTITLE="[ DNS ANYCAST SYSTEM ] - $NAME | $PHONE"

# ---------- Funções Auxiliares ----------

require_deps() {
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    whiptail sipcalc frr unbound dns-root-data zabbix-sender dnsutils curl
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
        WAN_IF=$(whiptail --backtitle "$BTITLE" --title " [ 02 - INTERFACE ] " --inputbox "Interface WAN principal (Ex: ens18):" 10 70 "ens18" 3>&1 1>&2 2>&3) || STEP=1
        [[ $? -eq 0 ]] && STEP=3
        ;;
      3)
        IPV4_CIDR=$(whiptail --backtitle "$BTITLE" --title " [ 03 - IPV4/CIDR ] " --inputbox "IPv4 Público com máscara (Ex: 198.18.1.10/27):" 10 70 "198.18.1.10/27" 3>&1 1>&2 2>&3) || STEP=2
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
        IPV6_PUB=$(whiptail --backtitle "$BTITLE" --title " [ 05 - IPV6/CIDR ] " --inputbox "IPv6 Público com máscara (Ex: 2001:db8::faca:198:18:1:10/64):" 10 70 "2001:db8::faca:198:18:1:10/64" 3>&1 1>&2 2>&3) || STEP=4
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
        LB_DATA=$(whiptail --backtitle "$BTITLE" --title " [ 07 - ANYCAST IPs ] " --inputbox "Lista exata: V4_1,V4_2,V6_1,V6_2" 10 70 "10.10.10.10,10.10.9.9,fd00::10:10:10:10,fd00::10:10:9:9" 3>&1 1>&2 2>&3) || STEP=6
        if [ $? -eq 0 ]; then
          IFS=',' read -r L1V4 L2V4 L1V6 L2V6 <<< "$LB_DATA"
          STEP=8
        fi
        ;;
      8)
        ACL_DATA=$(whiptail --backtitle "$BTITLE" --title " [ 08 - ACLs UNBOUND ] " --inputbox "Prefixos autorizados V4 e V6 (separados por vírgula):" 10 70 "198.18.0.0/22,2001:db8::/32" 3>&1 1>&2 2>&3) || STEP=7
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
  # Extraindo apenas os IPs puros (sem a barra do CIDR)
  IPV4_IP=$(echo "$IPV4_CIDR" | cut -d/ -f1)
  IPV6_IP=$(echo "$IPV6_PUB" | cut -d/ -f1)
  THREADS=$(nproc)

  # 1. Configuração de Rede Interfaces
  cat > /etc/network/interfaces <<EOF
# Gerado por $NAME | $PHONE
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
 ospf router-id $IPV4_IP
!
router ospf6
 ospf6 router-id $IPV4_IP
 redistribute connected
EOF

  # 3. Unbound Hyperlocal
  mkdir -p /etc/unbound/unbound.conf.d
  
  # Zona de bloqueio padrão RPZ
  cat > /etc/unbound/rpz.block.hosts.zone <<EOF
\$TTL 2h
@ IN SOA localhost. root.localhost. (2 6h 1h 1w 2h)
  IN NS  localhost.
; RPZ manual block hosts
EOF

  # Configuração Principal do Unbound Anycast
  cat > /etc/unbound/unbound.conf.d/local.conf <<EOF
server:
        verbosity: 1
        statistics-interval: 0
        statistics-cumulative: no
        extended-statistics: yes
        num-threads: $THREADS
        serve-expired: yes
        interface: 127.0.0.1
        interface: $L1V4
        interface: $L2V4
        interface: $IPV4_IP
        interface: $L1V6
        interface: $L2V6
        interface: ::1
        interface-automatic: no
        outgoing-interface: $IPV4_IP
        outgoing-interface: $IPV6_IP
        outgoing-range: 8192
        outgoing-num-tcp: 1024
        incoming-num-tcp: 2048
        so-rcvbuf: 4m
        so-sndbuf: 4m
        so-reuseport: yes
        edns-buffer-size: 1232
        msg-cache-size: 512m
        msg-cache-slabs: 4
        num-queries-per-thread: 4096
        rrset-cache-size: 1g
        rrset-cache-slabs: 4
        infra-cache-slabs: 4
        do-ip4: yes
        do-ip6: yes
        do-udp: yes
        do-tcp: yes
        chroot: ""
        username: "unbound"
        directory: "/etc/unbound"
        logfile: "/var/log/unbound/unbound.log"
        use-syslog: no
        log-time-ascii: yes
        log-queries: no
        pidfile: "/var/run/unbound.pid"
        root-hints: "/usr/share/dns/root.hints"
        hide-identity: yes
        hide-version: yes
        unwanted-reply-threshold: 10000000
        prefetch: yes
        prefetch-key: yes
        rrset-roundrobin: yes
        minimal-responses: yes
        module-config: "respip validator iterator"
        val-clean-additional: yes
        val-log-level: 1
        key-cache-slabs: 4
        deny-any: yes
        cache-min-ttl: 60
        key-cache-size: 128m
        neg-cache-size: 64m
        cache-max-ttl: 86400
        infra-cache-numhosts: 100000
        access-control: $ACL_V4 allow
        access-control: $ACL_V6 allow
 
rpz:
  name: rpz.block.host.local.zone
  zonefile: /etc/unbound/rpz.block.hosts.zone
  rpz-action-override: nxdomain
 
auth-zone:
    name: "."
    master: "b.root-servers.net"
    master: "c.root-servers.net"
    master: "d.root-servers.net"
    master: "f.root-servers.net"
    master: "g.root-servers.net"
    master: "k.root-servers.net"
    master: "lax.xfr.dns.icann.org"
    master: "iad.xfr.dns.icann.org"
    fallback-enabled: yes
    for-downstream: no
    for-upstream: yes
    zonefile: "/var/lib/unbound/root.zone"

auth-zone:
    name: "arpa."
    master: "lax.xfr.dns.icann.org"
    master: "iad.xfr.dns.icann.org"
    fallback-enabled: yes
    for-downstream: no
    for-upstream: yes
    zonefile: "/var/lib/unbound/arpa.zone"
EOF

  # 4. Ajustar permissões e reiniciar serviços
  chown -R unbound:unbound /etc/unbound /var/log/unbound
  systemctl restart networking || true
  systemctl restart frr || true
  systemctl restart unbound || true
}

# ---------- MAIN ----------

main() {
  clear
  require_deps
  collect_params
  draw_progress "Aplicando configurações do Sistema (Rede, OSPF, Unbound)..."
  apply_configs
  whiptail --backtitle "$BTITLE" --title " INSTALAÇÃO CONCLUÍDA " --msgbox "O servidor foi configurado seguindo as diretrizes de alta performance Anycast + Hyperlocal.\n\nAutor: $NAME\nContato: $PHONE" 12 70
  clear
}

main "$@"
