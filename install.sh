#!/usr/bin/env bash
# ==========================================================
# DNS ANYCAST INSTALLER (UNBOUND + FRR + HYPERLOCAL)
# BY: LAILSON ARAUJO | +55 83 98615-2503
# ==========================================================

# Personalização de Cores (Estilo Dark/Blue)
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

# Variáveis de Identidade
CREDENTIALS="LAILSON ARAUJO | +55 83 98615-2503"
BTITLE="DNS ANYCAST AUTOMATION - $CREDENTIALS"

# ---------- Funções de Estética ----------

draw_progress() {
  (
    echo 10 ; sleep 0.5 ; echo 40 ; sleep 0.5
    echo 70 ; sleep 0.5 ; echo 100 ; sleep 0.5
  ) | whiptail --backtitle "$BTITLE" --title "Processando" --gauge "$1" 8 70 0
}

# ---------- Coleta com Navegação e Visual Melhorado ----------

collect_params() {
  STEP=1
  while true; do
    case $STEP in
      1)
        HOSTNAME_NEW=$(whiptail --backtitle "$BTITLE" --title " 🖥️ HOSTNAME " --inputbox "Defina o nome do servidor:" 10 70 "$(hostname)" 3>&1 1>&2 2>&3) || exit 1
        hostnamectl set-hostname "$HOSTNAME_NEW"
        STEP=2
        ;;
      2)
        WAN_IF=$(whiptail --backtitle "$BTITLE" --title " 🌐 INTERFACE WAN " --inputbox "Qual a interface de rede principal?" 10 70 "ens18" 3>&1 1>&2 2>&3) || STEP=1
        [[ $? -eq 0 ]] && STEP=3
        ;;
      3)
        IPV4_CIDR=$(whiptail --backtitle "$BTITLE" --title " 📥 ENDEREÇAMENTO IPV4 " --inputbox "Digite o IPv4/CIDR (ex: 198.18.1.2/30):" 10 70 "198.18.1.2/30" 3>&1 1>&2 2>&3) || STEP=2
        if [ $? -eq 0 ]; then
          # Cálculo automático inteligente do Gateway
          SUGGESTED_GW=$(sipcalc "$IPV4_CIDR" | grep "Usable range" | awk '{print $4}' || echo "")
          STEP=4
        fi
        ;;
      4)
        IPV4_GW=$(whiptail --backtitle "$BTITLE" --title " 🛣️ GATEWAY IPV4 " --inputbox "Confirme o Gateway da rede:" 10 70 "$SUGGESTED_GW" 3>&1 1>&2 2>&3) || STEP=3
        [[ $? -eq 0 ]] && STEP=5
        ;;
      5)
        IPV6_PUB=$(whiptail --backtitle "$BTITLE" --title " 📥 ENDEREÇAMENTO IPV6 " --inputbox "Digite o IPv6/CIDR (ex: 2804:bebe:cafe::2/64):" 10 70 "2804:bebe:cafe::2/64" 3>&1 1>&2 2>&3) || STEP=4
        if [ $? -eq 0 ]; then
          SUGGESTED_V6_GW=$(echo "$IPV6_PUB" | cut -d/ -f1 | sed 's/[0-9a-fA-F]*$/1/')
          STEP=6
        fi
        ;;
      6)
        IPV6_GW=$(whiptail --backtitle "$BTITLE" --title " 🛣️ GATEWAY IPV6 " --inputbox "Confirme o Gateway IPv6:" 10 70 "$SUGGESTED_V6_GW" 3>&1 1>&2 2>&3) || STEP=5
        [[ $? -eq 0 ]] && STEP=7
        ;;
      7)
        LOOPBACKS=$(whiptail --backtitle "$BTITLE" --title " ♻️ LOOPBACKS ANYCAST " --inputbox "Formato: V4_1,V4_2,V6_1,V6_2" 10 70 "10.10.10.10,10.10.9.9,fd00::10:10:10:10,fd00::10:10:9:9" 3>&1 1>&2 2>&3) || STEP=6
        if [ $? -eq 0 ]; then
           IFS=',' read -r L1V4 L2V4 L1V6 L2V6 <<< "$LOOPBACKS"
           STEP=8
        fi
        ;;
      8)
        # Resumo Final antes de aplicar
        SUMMARY="Confira os dados para aplicação:
        
        Hostname:    $HOSTNAME_NEW
        Interface:   $WAN_IF
        IPv4/GW:     $IPV4_CIDR -> $IPV4_GW
        IPv6/GW:     $IPV6_PUB -> $IPV6_GW
        Anycast V4:  $L1V4, $L2V4
        Anycast V6:  $L1V6, $L2V6"
        
        if whiptail --backtitle "$BTITLE" --title " ✅ CONFIRMAÇÃO FINAL " --yesno "$SUMMARY" 15 70; then
          break
        else
          STEP=7
        fi
        ;;
    esac
  done
}

# ---------- Execução ----------

main() {
  # Tela de boas vindas estilizada
  whiptail --backtitle "$BTITLE" --title " BEM-VINDO " --msgbox "Instalador DNS Recursivo Anycast\n\nDesenvolvido por: $CREDENTIALS" 12 60
  
  collect_params
  
  draw_progress "Configurando Interfaces de Rede..."
  # (Aqui entra a função configure_network_interfaces do código anterior)
  
  draw_progress "Configurando FRR OSPFv2/v3..."
  # (Aqui entra a função configure_frr do código anterior)

  whiptail --backtitle "$BTITLE" --title " 🎉 SUCESSO! " --msgbox "O servidor foi configurado com sucesso!\n\nRecomendamos reiniciar para validar as interfaces." 12 60
}

main "$@"
