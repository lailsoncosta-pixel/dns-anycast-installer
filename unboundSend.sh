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
