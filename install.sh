#!/usr/bin/env bash
# ==========================================================
# DNS ANYCAST INSTALLER (UNBOUND + FRR + HYPERLOCAL)
# Automação completa com interface WHIPTAIL (TUI)
# BY: LAILSON ARAUJO
# Contato: +55 83 98615-2503
# Alvo: Debian 12 (Bookworm)
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
    echo "Você pode adaptar para outras versões, mas por sua conta e risco."
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
    --msgbox "Bem-vindo ao instalador automatizado do DNS Recursivo Anycast (Unbound + FRR + Hyperlocal).\n\nPressione OK para continuar." 0 0

  HOSTNAME_NEW=$(ask_input "Hostname" "Informe o hostname deste servidor DNS (sem domínio):" "$(hostname)")
  hostnamectl set-hostname "$HOSTNAME_NEW"

  WAN_IF=$(ask_input "Interface WAN" "Informe o nome da interface principal (WAN). Ex: ens18" "ens18")

  IPV4_PUB=$(ask_input "IPv4 público" "Informe o IPv4 PÚBLICO usado para recursividade (ex: 198.18.1.10):" "198.18.1.10")
  IPV4_PUB_CIDR=$(ask_input "Máscara IPv4" "Informe a máscara em CIDR do IPv4 público (ex: 27 para /27):" "27")
  IPV4_GW=$(ask_input "Gateway IPv4" "Informe o gateway IPv4 (ex: 198.18.1.1):" "198.18.1.1")

  IPV6_PUB=$(ask_input "IPv6 público" "Informe o IPv6 PÚBLICO usado para recursividade (ex: 2001:db8::faca:198:18:1:10):" "2001:db8::faca:198:18:1:10")
  IPV6_PUB_CIDR=$(ask_input "Máscara IPv6" "Informe o prefixo IPv6 em CIDR (ex: 64 para /64):" "64")
  IPV6_GW=$(ask_input "Gateway IPv6" "Informe o gateway IPv6 (ex: 2001:db8::faca:198:18:1:1):" "2001:db8::faca:198:18:1:1")

  LOOPBACK1_V4=$(ask_input "Loopback Anycast IPv4 1" "Informe o IPv4 Anycast loopback 1 (ex: 10.10.10.10):" "10.10.10.10")
  LOOPBACK2_V4=$(ask_input "Loopback Anycast IPv4 2" "Informe o IPv4 Anycast loopback 2 (ex: 10.10.9.9):" "10.10.9.9")

  LOOPBACK1_V6=$(ask_input "Loopback Anycast IPv6 1" "Informe o IPv6 Anycast loopback 1 (ex: fd00::10:10:10:10):" "fd00::10:10:10:10")
  LOOPBACK2_V6=$(ask_input "Loopback Anycast IPv6 2" "Informe o IPv6 Anycast loopback 2 (ex: fd00::10:10:9:9):" "fd00::10:10:9:9")

  LINK_V4=$(ask_input "Endereço /30" "Informe o IPv4 deste servidor no /30 até o PE (ex: 172.16.0.6):" "172.16.0.6")
  LINK_V4_CIDR=$(ask_input "CIDR /30" "Informe o CIDR desse /30 (ex: 30 para /30):" "30")
  LINK_PE_V4=$(ask_input "IP do PE" "Informe o IPv4 do PE na outra ponta do /30 (ex: 172.16.0.5):" "172.16.0.5")

  ACL_V4=$(ask_input "ACL IPv4" "Informe os prefixos IPv4 autorizados a usar este recursivo (separados por vírgula).\nEx: 198.18.0.0/22,10.0.0.0/8" "198.18.0.0/22")
  ACL_V6=$(ask_input "ACL IPv6" "Informe os prefixos IPv6 autorizados a usar este recursivo (separados por vírgula).\nEx: 2001:db8::/32" "2001:db8::/32")

  if ask_yesno "Zabbix" "Deseja habilitar envio de métricas do Unbound para Zabbix?"; then
    ENABLE_ZABBIX=1
    ZABBIX_IP=$(ask_input "Zabbix Server" "Informe o IP do servidor Zabbix:" "192.168.10.1")
    ZABBIX_HOSTNAME=$(ask_input "Hostname no Zabbix" "Informe o nome deste host no Zabbix:" "$HOSTNAME_NEW")
  else
    ENABLE_ZABBIX=0
    ZABBIX_IP=""
    ZABBIX_HOSTNAME=""
  fi

  if ask_yesno "DoH (DNS over HTTPS)" "Deseja habilitar suporte a DoH (DNS over HTTPS) no Unbound?\n(É necessário ter certificado válido depois)"; then
    ENABLE_DOH=1
    DOH_DOMAIN=$(ask_input "Domínio DoH" "Informe o FQDN que será usado para DoH (ex: doh.seudominio.com):" "doh.example.com")
  else
    ENABLE_DOH=0
    DOH_DOMAIN=""
  fi

  if ask_yesno "Telegram" "Deseja preparar o script de checagem para poder enviar alertas via Telegram (você configura depois o telegram-notify)?"; then
    ENABLE_TELEGRAM=1
  else
    ENABLE_TELEGRAM=0
  fi
}

show_summary() {
  local summary="
Hostname:           $HOSTNAME_NEW

Interface WAN:      $WAN_IF

IPv4 público:       $IPV4_PUB/$IPV4_PUB_CIDR  (GW: $IPV4_GW)
IPv6 público:       $IPV6_PUB/$IPV6_PUB_CIDR  (GW: $IPV6_GW)

Loopbacks Anycast:
  IPv4:             $LOOPBACK1_V4, $LOOPBACK2_V4
  IPv6:             $LOOPBACK1_V6, $LOOPBACK2_V6

Link /30 até PE:
  IP local:         $LINK_V4/$LINK_V4_CIDR
  IP PE:            $LINK_PE_V4

ACLs:
  IPv4:             $ACL_V4
  IPv6:             $ACL_V6

Zabbix:             $( [[ ${ENABLE_ZABBIX:-0} -eq 1 ]] && echo "SIM ($ZABBIX_IP, host: $ZABBIX_HOSTNAME)" || echo "NÃO" )
DoH:                $( [[ ${ENABLE_DOH:-0} -eq 1 ]] && echo "SIM ($DOH_DOMAIN)" || echo "NÃO" )
Telegram:           $( [[ ${ENABLE_TELEGRAM:-0} -eq 1 ]] && echo "SIM (ajuste depois o telegram-notify)" || echo "NÃO" )

BY: LAILSON ARAUJO — Contato: +55 83 98615-2503
"

  whiptail --title "Resumo da configuração" --msgbox "$summary" 0 0
  if ! ask_yesno "Confirmar" "Deseja prosseguir com a instalação com estes parâmetros?"; then
    echo "Instalação cancelada."
    exit 1
  fi
}

# ---------- Etapas de instalação ----------

configure_apt_sources() {
  cat > /etc/apt/sources.list <<EOF
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
EOF
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
}

install_base_packages() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    net-tools nftables htop iotop sipcalc tcpdump curl gnupg rsync wget host dnsutils mtr-tiny bmon sudo tmux whois ethtool dnstop \
    chrony \
    unbound dns-root-data \
    logrotate \
    zabbix-sender \
    python3 \
    iproute2 \
    frr frr-pythontools frr-doc || true
}

tune_sysctl_nf_conntrack() {
  cat >> /etc/sysctl.conf <<'EOF'

# Ajustes para DNS Recursivo Anycast — BY: LAILSON ARAUJO (+55 83 98615-2503)
net.core.rmem_max = 2147483647
net.core.wmem_max = 2147483647
net.ipv4.tcp_rmem = 4096 87380 2147483647
net.ipv4.tcp_wmem = 4096 65536 2147483647
net.netfilter.nf_conntrack_buckets = 512000
net.netfilter.nf_conntrack_max = 4096000
vm.swappiness=10
EOF

  if ! grep -q '^nf_conntrack$' /etc/modules 2>/dev/null; then
    echo nf_conntrack >> /etc/modules
  fi
  modprobe nf_conntrack || true
  sysctl -p || true
}

configure_network_interfaces() {
  cat > /etc/network/interfaces <<EOF
# Arquivo gerado pelo DNS Anycast Installer
# BY: LAILSON ARAUJO — Contato: +55 83 98615-2503

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
      address $IPV6_PUB/$IPV6_PUB_CIDR
      gateway $IPV6_GW

auto ${WAN_IF}:0
iface ${WAN_IF}:0 inet static
      address $LINK_V4/$LINK_V4_CIDR
EOF

  systemctl restart networking || true
}

disable_thp() {
  cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Desativa Transparent Huge Pages (THP)
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now disable-thp || true
}

configure_chrony() {
  cat > /etc/chrony/chrony.conf <<'EOF'
pool 2.debian.pool.ntp.org iburst

server a.st1.ntp.br iburst nts
server b.st1.ntp.br iburst nts
server c.st1.ntp.br iburst nts
server d.st1.ntp.br iburst nts

driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony/chrony.keys
logdir /var/log/chrony
EOF
  systemctl restart chronyd.service || systemctl restart chrony.service || true
}

configure_unbound_logrotate() {
  mkdir -p /var/log/unbound
  touch /var/log/unbound/unbound.log
  chown -R unbound:unbound /var/log/unbound

  cat > /etc/logrotate.d/unbound <<'EOF'
/var/log/unbound/unbound.log {
    rotate 5
    weekly
    postrotate
        unbound-control log_reopen
    endscript
}
EOF

  systemctl restart logrotate.service || true
}

configure_unbound() {
  mkdir -p /etc/unbound/unbound.conf.d
  mkdir -p /var/lib/unbound
  chown unbound:unbound /var/lib/unbound

  local acl_v4_lines=""
  IFS=',' read -ra v4arr <<< "$ACL_V4"
  for p in "${v4arr[@]}"; do
    p_trimmed=$(echo "$p" | xargs)
    [[ -n "$p_trimmed" ]] && acl_v4_lines+="        access-control: $p_trimmed allow\n"
  done

  local acl_v6_lines=""
  IFS=',' read -ra v6arr <<< "$ACL_V6"
  for p in "${v6arr[@]}"; do
    p_trimmed=$(echo "$p" | xargs)
    [[ -n "$p_trimmed" ]] && acl_v6_lines+="        access-control: $p_trimmed allow\n"
  done

  local doh_block=""
  if [[ ${ENABLE_DOH:-0} -eq 1 ]]; then
    doh_block=$(cat <<EOF_DOH
        interface: $LOOPBACK1_V4@443
        interface: $LOOPBACK2_V4@443
        interface: $LOOPBACK1_V6@443
        interface: $LOOPBACK2_V6@443
        tls-service-key: "/etc/letsencrypt/live/$DOH_DOMAIN/privkey.pem"
        tls-service-pem: "/etc/letsencrypt/live/$DOH_DOMAIN/fullchain.pem"
EOF_DOH
)
  fi

  cat > /etc/unbound/unbound.conf.d/local.conf <<EOF
# Configuração gerada pelo DNS Anycast Installer
# BY: LAILSON ARAUJO — Contato: +55 83 98615-2503

server:
        verbosity: 1
        statistics-interval: 0
        statistics-cumulative: no
        extended-statistics: yes
        num-threads: 4
        serve-expired: yes

        interface: 127.0.0.1
        interface: ::1
        interface: $LOOPBACK1_V4
        interface: $LOOPBACK2_V4
        interface: $LINK_V4
        interface: $LOOPBACK1_V6
        interface: $LOOPBACK2_V6
$doh_block
        interface-automatic: no

        outgoing-interface: $IPV4_PUB
        outgoing-interface: $IPV6_PUB

        outgoing-range: 8192
        outgoing-num-tcp: 1024
        incoming-num-tcp: 2048
        so-rcvbuf: 4m
        so-sndbuf: 4m
        so-reuseport: yes
        edns-buffer-size: 1232
        msg-cache-size: 1g
        msg-cache-slabs: 4
        num-queries-per-thread: 4096
        rrset-cache-size: 2g
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
$(printf "%b" "$acl_v4_lines")
$(printf "%b" "$acl_v6_lines")

rpz:
  name: rpz.block.host.local.zone
  zonefile: /etc/unbound/rpz.block.hosts.zone
  rpz-action-override: nxdomain

python:

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

  cat > /etc/unbound/rpz.block.hosts.zone <<'EOF'
$TTL 2h
@ IN SOA localhost. root.localhost. (2 6h 1h 1w 2h)
  IN NS  localhost.
; RPZ manual block hosts
;*.exemplo-bloqueio.com CNAME .
;exemplo-bloqueio.com CNAME .
EOF

  systemctl enable --now unbound
}

configure_resolvconf() {
  cat > /etc/resolv.conf <<'EOF'
# resolv.conf para o próprio servidor (DNS externo apenas para emergências)
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2001:4860:4860::8888
EOF
}

install_unbound_zabbix_sender_script() {
  [[ ${ENABLE_ZABBIX:-0} -eq 1 ]] || return 0

  mkdir -p /root/scripts
  cat > /root/scripts/unboundSend.sh <<'EOF'
#!/bin/bash
# Envio de métricas do Unbound para Zabbix
# BY: LAILSON ARAUJO — Contato: +55 83 98615-2503

if [ -z "${1}" ] || [ -z "${2}" ] ; then
        echo "Uso: ./unboundSend.sh IP_ZABBIX HOSTNAME"
        exit 1
fi

IP_ZABBIX=$1
NAME_HOST=$2
DIR_TEMP=/var/tmp/
FILE="${DIR_TEMP}dump_unbound_control_stats.txt"
unbound-control stats > ${FILE}

TOTAL_NUM_QUERIES=$(grep -w 'total.num.queries' ${FILE} | cut -d '=' -f2)
TOTAL_NUM_CACHEHITS=$(grep -w 'total.num.cachehits' ${FILE} | cut -d '=' -f2)
TOTAL_NUM_CACHEMISS=$(grep -w 'total.num.cachemiss' ${FILE} | cut -d '=' -f2)
TOTAL_NUM_PREFETCH=$(grep -w 'total.num.prefetch' ${FILE} | cut -d '=' -f2)
TOTAL_NUM_RECURSIVEREPLIES=$(grep -w 'total.num.recursivereplies' ${FILE} | cut -d '=' -f2)

TOTAL_REQ_MAX=$(grep -w 'total.requestlist.max' ${FILE} | cut -d '=' -f2)
TOTAL_REQ_AVG=$(grep -w 'total.requestlist.avg' ${FILE} | cut -d '=' -f2)
TOTAL_REQ_OVERWRITTEN=$(grep -w 'total.requestlist.overwritten' ${FILE} | cut -d '=' -f2)
TOTAL_REQ_EXCEEDED=$(grep -w 'total.requestlist.exceeded' ${FILE} | cut -d '=' -f2)
TOTAL_REQ_CURRENT_ALL=$(grep -w 'total.requestlist.current.all' ${FILE} | cut -d '=' -f2)
TOTAL_REQ_CURRENT_USER=$(grep -w 'total.requestlist.current.user' ${FILE} | cut -d '=' -f2)

TOTAL_TCPUSAGE=$(grep -w 'total.tcpusage' ${FILE} | cut -d '=' -f2)

NUM_QUERY_TYPE_A=$(grep -w 'num.query.type.A' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_NS=$(grep -w 'num.query.type.NS' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_MX=$(grep -w 'num.query.type.MX' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_TXT=$(grep -w 'num.query.type.TXT' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_PTR=$(grep -w 'num.query.type.PTR' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_AAAA=$(grep -w 'num.query.type.AAAA' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_SRV=$(grep -w 'num.query.type.SRV' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_SOA=$(grep -w 'num.query.type.SOA' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_HTTPS=$(grep -w 'num.query.type.HTTPS' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_TYPE0=$(grep -w 'num.query.type.TYPE0' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_CNAME=$(grep -w 'num.query.type.CNAME' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_WKS=$(grep -w 'num.query.type.WKS' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_HINFO=$(grep -w 'num.query.type.HINFO' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_X25=$(grep -w 'num.query.type.X25' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_NAPTR=$(grep -w 'num.query.type.NAPTR' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_DS=$(grep -w 'num.query.type.DS' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_DNSKEY=$(grep -w 'num.query.type.DNSKEY' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_TLSA=$(grep -w 'num.query.type.TLSA' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_SVCB=$(grep -w 'num.query.type.SVCB' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_SPF=$(grep -w 'num.query.type.SPF' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_ANY=$(grep -w 'num.query.type.ANY' ${FILE} | cut -d '=' -f2)
NUM_QUERY_TYPE_OTHER=$(grep -w 'num.query.type.other' ${FILE} | cut -d '=' -f2)

NUM_ANSWER_RCODE_NOERROR=$(grep -w 'num.answer.rcode.NOERROR' ${FILE} | cut -d '=' -f2)
NUM_ANSWER_RCODE_NXDOMAIN=$(grep -w 'num.answer.rcode.NXDOMAIN' ${FILE} | cut -d '=' -f2)
NUM_ANSWER_RCODE_SERVFAIL=$(grep -w 'num.answer.rcode.SERVFAIL' ${FILE} | cut -d '=' -f2)
NUM_ANSWER_RCODE_REFUSED=$(grep -w 'num.answer.rcode.REFUSED' ${FILE} | cut -d '=' -f2)
NUM_ANSWER_RCODE_nodata=$(grep -w 'num.answer.rcode.nodata' ${FILE} | cut -d '=' -f2)
NUM_ANSWER_secure=$(grep -w 'num.answer.secure' ${FILE} | cut -d '=' -f2)

send() {
  local key=$1
  local val=$2
  [ -z "$val" ] || zabbix_sender -z ${IP_ZABBIX} -s ${NAME_HOST} -k "$key" -o $((val/300))
}

send total.num.queries "$TOTAL_NUM_QUERIES"
send total.num.cachehits "$TOTAL_NUM_CACHEHITS"
send total.num.cachemiss "$TOTAL_NUM_CACHEMISS"
send total.num.prefetch "$TOTAL_NUM_PREFETCH"
send total.num.recursivereplies "$TOTAL_NUM_RECURSIVEREPLIES"

send total.requestlist.max "$TOTAL_REQ_MAX"
send total.requestlist.avg "$TOTAL_REQ_AVG"
send total.requestlist.overwritten "$TOTAL_REQ_OVERWRITTEN"
send total.requestlist.exceeded "$TOTAL_REQ_EXCEEDED"
send total.requestlist.current.all "$TOTAL_REQ_CURRENT_ALL"
send total.requestlist.current.user "$TOTAL_REQ_CURRENT_USER"

send total.tcpusage "$TOTAL_TCPUSAGE"

send num.query.a "$NUM_QUERY_TYPE_A"
send num.query.ns "$NUM_QUERY_TYPE_NS"
send num.query.mx "$NUM_QUERY_TYPE_MX"
send num.query.txt "$NUM_QUERY_TYPE_TXT"
send num.query.ptr "$NUM_QUERY_TYPE_PTR"
send num.query.aaaa "$NUM_QUERY_TYPE_AAAA"
send num.query.srv "$NUM_QUERY_TYPE_SRV"
send num.query.soa "$NUM_QUERY_TYPE_SOA"
send num.query.https "$NUM_QUERY_TYPE_HTTPS"
send num.query.type0 "$NUM_QUERY_TYPE_TYPE0"
send num.query.cname "$NUM_QUERY_TYPE_CNAME"
send num.query.wks "$NUM_QUERY_TYPE_WKS"
send num.query.hinfo "$NUM_QUERY_TYPE_HINFO"
send num.query.X25 "$NUM_QUERY_TYPE_X25"
send num.query.naptr "$NUM_QUERY_TYPE_NAPTR"
send num.query.ds "$NUM_QUERY_TYPE_DS"
send num.query.dnskey "$NUM_QUERY_TYPE_DNSKEY"
send num.query.tlsa "$NUM_QUERY_TYPE_TLSA"
send num.query.svcb "$NUM_QUERY_TYPE_SVCB"
send num.query.spf "$NUM_QUERY_TYPE_SPF"
send num.query.any "$NUM_QUERY_TYPE_ANY"
send num.query.other "$NUM_QUERY_TYPE_OTHER"

send num.answer.rcode.NOERROR "$NUM_ANSWER_RCODE_NOERROR"
send num.answer.rcode.NXDOMAIN "$NUM_ANSWER_RCODE_NXDOMAIN"
send num.answer.rcode.SERVFAIL "$NUM_ANSWER_RCODE_SERVFAIL"
send num.answer.rcode.REFUSED "$NUM_ANSWER_RCODE_REFUSED"
send num.answer.rcode.nodata "$NUM_ANSWER_RCODE_nodata"
send num.answer.secure "$NUM_ANSWER_secure"
EOF

  chmod 700 /root/scripts/unboundSend.sh

  if ! grep -q "unboundSend.sh" /etc/crontab; then
    echo "*/5 * * * *     root    /root/scripts/unboundSend.sh $ZABBIX_IP $ZABBIX_HOSTNAME 1> /dev/null" >> /etc/crontab
  fi
}

install_checa_dns_script() {
  mkdir -p /root/scripts
  cat > /root/scripts/checa_dns.sh <<EOF
#!/usr/bin/env bash
# Script de teste de recursividade do Unbound + failover OSPF
# BY: LAILSON ARAUJO — Contato: +55 83 98615-2503

dominios_testar=(
www.google.com
www.terra.com.br
www.uol.com.br
www.globo.com
www.facebook.com
www.youtube.com
www.twitch.com
www.discord.com
www.debian.org
www.redhat.com
)

corte_taxa_falha=100

remove_ospf() {
   habilitado="\$(vtysh -c 'show run' | grep "LOOPBACKS")"
   if [ "\$habilitado" != "" ]; then
      vtysh -c 'conf t' -c 'interface lo' -c 'no description' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ip ospf area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ip ospf passive' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ipv6 ospf6 area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ipv6 ospf6 passive' -c 'end' -c 'wr'
      $( [[ ${ENABLE_TELEGRAM:-0} -eq 1 ]] and 'echo "Servidor $HOSTNAME morreu!" | /usr/local/sbin/telegram-notify --error --text -' or 'true' )
   fi
}

adiciona_ospf() {
   habilitado="\$(vtysh -c 'show run' | grep "LOOPBACKS")"
   if [ "\$habilitado" == "" ]; then
      vtysh -c 'conf t' -c 'interface lo' -c 'description LOOPBACKS' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ip ospf area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ip ospf passive' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ipv6 ospf6 area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ipv6 ospf6 passive' -c 'end' -c 'wr'
      $( [[ ${ENABLE_TELEGRAM:-0} -eq 1 ]] and 'echo "Servidor $HOSTNAME retornou do inferno!" | /usr/local/sbin/telegram-notify --success --text -' or 'true' )
   fi
}

systemctl status unbound &> /dev/null
if [ \$? -ne 0 ]; then
   $( [[ ${ENABLE_TELEGRAM:-0} -eq 1 ]] and 'echo "Servidor $HOSTNAME morreu DNS mas tentando levantar!" | /usr/local/sbin/telegram-notify --error --text -' or 'true' )
   systemctl restart unbound
   systemctl status unbound &> /dev/null
   if [ \$? -ne 0 ]; then
      remove_ospf
      exit
   fi
   $( [[ ${ENABLE_TELEGRAM:-0} -eq 1 ]] and 'echo "Servidor $HOSTNAME servico DNS voltou mas tinha morrido!" | /usr/local/sbin/telegram-notify --success --text -' or 'true' )
fi

qt_falhas=0
qt_total="\${#dominios_testar[@]}"
echo "total_dominios: \$qt_total"
for site in "\${dominios_testar[@]}"
do
  unbound-control flush \$site &> /dev/null
  resolver="127.0.0.1"
  echo -e " - dominio \$site - \$resolver - \c"
  host \$site \$resolver &> /dev/null
  if [ \$? -ne 0 ]; then
     ((qt_falhas++))
     echo -e "[Falhou]"
  else
     echo -e "[OK]"
  fi
done

taxa_falha=\$((qt_falhas*100/qt_total))
echo "Falhas \$qt_falhas/\$qt_total (\$taxa_falha%)"

if [ "\$taxa_falha" -ge "\$corte_taxa_falha" ]; then
   remove_ospf
   exit
fi
adiciona_ospf
EOF

  chmod 700 /root/scripts/checa_dns.sh

  if ! grep -q "checa_dns.sh" /etc/crontab; then
    echo "*/1 *   * * *   root    /root/scripts/checa_dns.sh" >> /etc/crontab
  fi
}

# ---------- MAIN ----------

main() {
  require_root
  require_debian_12
  require_whiptail
  collect_params
  show_summary

  whiptail --title "Instalação" --msgbox "Iniciando instalação. Isso pode levar alguns minutos." 0 0

  configure_apt_sources
  install_base_packages
  tune_sysctl_nf_conntrack
  configure_network_interfaces
  disable_thp
  configure_chrony
  configure_unbound_logrotate
  configure_unbound
  configure_resolvconf
  install_unbound_zabbix_sender_script
  install_checa_dns_script

  whiptail --title "Concluído" --msgbox "Instalação concluída!\n\n- Verifique /etc/frr (se necessário, ajuste manualmente).\n- Se habilitou DoH, gere o certificado Let's Encrypt para $DOH_DOMAIN.\n- Um reboot é recomendado.\n\nBY: LAILSON ARAUJO — Contato: +55 83 98615-2503" 0 0

  echo "Instalação finalizada. Recomenda-se reboot do servidor."
}

main "$@"
