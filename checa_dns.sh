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
   habilitado="$(vtysh -c 'show run' | grep "LOOPBACKS")"
   if [ "$habilitado" != "" ]; then
      vtysh -c 'conf t' -c 'interface lo' -c 'no description' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ip ospf area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ip ospf passive' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ipv6 ospf6 area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'no ipv6 ospf6 passive' -c 'end' -c 'wr'
      # Para usar Telegram, instale e configure /usr/local/sbin/telegram-notify
      # echo "Servidor $HOSTNAME morreu!" | /usr/local/sbin/telegram-notify --error --text -
   fi
}

adiciona_ospf() {
   habilitado="$(vtysh -c 'show run' | grep "LOOPBACKS")"
   if [ "$habilitado" == "" ]; then
      vtysh -c 'conf t' -c 'interface lo' -c 'description LOOPBACKS' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ip ospf area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ip ospf passive' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ipv6 ospf6 area 0.0.0.0' -c 'end' -c 'wr'
      vtysh -c 'conf t' -c 'interface lo' -c 'ipv6 ospf6 passive' -c 'end' -c 'wr'
      # echo "Servidor $HOSTNAME retornou do inferno!" | /usr/local/sbin/telegram-notify --success --text -
   fi
}

systemctl status unbound &> /dev/null
if [ $? -ne 0 ]; then
   # echo "Servidor $HOSTNAME morreu DNS mas tentando levantar!" | /usr/local/sbin/telegram-notify --error --text -
   systemctl restart unbound
   systemctl status unbound &> /dev/null
   if [ $? -ne 0 ]; then
      remove_ospf
      exit
   fi
   # echo "Servidor $HOSTNAME servico DNS voltou mas tinha morrido!" | /usr/local/sbin/telegram-notify --success --text -
fi

qt_falhas=0
qt_total="${#dominios_testar[@]}"
echo "total_dominios: $qt_total"
for site in "${dominios_testar[@]}"
do
  unbound-control flush $site &> /dev/null
  resolver="127.0.0.1"
  echo -e " - dominio $site - $resolver - \c"
  host $site $resolver &> /dev/null
  if [ $? -ne 0 ]; then
     ((qt_falhas++))
     echo -e "[Falhou]"
  else
     echo -e "[OK]"
  fi
done

taxa_falha=$((qt_falhas*100/qt_total))
echo "Falhas $qt_falhas/$qt_total ($taxa_falha%)"

if [ "$taxa_falha" -ge "$corte_taxa_falha" ]; then
   remove_ospf
   exit
fi
adiciona_ospf
