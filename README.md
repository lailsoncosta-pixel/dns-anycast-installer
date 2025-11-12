# DNS Anycast Installer  
Instalador automatizado para a implantação completa de um **DNS Recursivo Anycast** utilizando **Unbound + FRRouting (OSPF) + Hyperlocal**, ideal para Provedores de Internet (ISP) e infraestruturas que exigem alta performance, segurança e resiliência.

Este instalador é baseado em arquiteturas reais utilizadas em ISPs do Brasil e segue as melhores práticas do mercado.

BY: **LAILSON ARAUJO**  
Contato: **+55 83 98615-2503**

---

## 🚀 Recursos

- ✔ Instalação totalmente interativa (via whiptail)
- ✔ Configuração completa do Unbound
- ✔ Hyperlocal das zonas raiz (`.`) e `arpa.`
- ✔ Configuração automática do FRR (estrutura pronta)
- ✔ Suporte nativo a Anycast (loopbacks IPv4 e IPv6)
- ✔ Instalação opcional de:
  - DoH (DNS over HTTPS)
  - Monitoramento via Zabbix
  - Notificações via Telegram (via `telegram-notify`)
- ✔ THP desabilitado (melhor performance)
- ✔ Tuning de sysctl e conntrack
- ✔ Cronjobs de monitoramento e failover automático
- ✔ RPZ (Response Policy Zones) básica

---

## 📁 Estrutura do Repositório

```text
dns-anycast-installer/
│
├── install.sh                  # Script principal (instalador interativo)
├── README.md                   # Este arquivo
├── LICENSE                     # Licença MIT
├── .gitignore
│
└── scripts/
    ├── checa_dns.sh            # Script de saúde + failover OSPF
    └── unboundSend.sh          # Envio de métricas para Zabbix
```

---

## 🧰 Pré-requisitos

- Debian 12 (Bookworm) – instalação mínima
- Acesso root
- Acesso à Internet
- Conhecimento básico sobre:
  - OSPF
  - Anycast
  - Configuração de rede

---

## 🔧 Instalação

### 1. Clone o repositório

```bash
git clone https://github.com/SEU_USUARIO/dns-anycast-installer.git
cd dns-anycast-installer
chmod +x install.sh
```

### 2. Execute o instalador

```bash
sudo ./install.sh
```

O instalador irá abrir janelas interativas onde você irá informar:

- Nome do servidor  
- Interface WAN  
- IPv4 e IPv6 públicos  
- Loopbacks Anycast  
- Endereço /30 com o PE  
- Prefixos ACL  
- Domínio para DoH (opcional)  
- IP do Zabbix Server (opcional)  
- Se deseja ativar scripts de failover, DoH, RPZ, Telegram etc.  

---

## 🧠 O que o script configura automaticamente?

### 🔵 Rede e Roteamento
- Criação total do `/etc/network/interfaces`
- Loopbacks Anycast IPv4 e IPv6
- IPs públicos e /30 até o PE
- Ajustes de sysctl e conntrack
- Estrutura pronta para uso com FRR/OSPF

> ⚠ Você ainda pode querer ajustar manualmente `/etc/frr` conforme sua topologia específica.

### 🟢 Unbound
- DNSSEC habilitado
- Hyperlocal para:
  - `.`
  - `arpa.`
- Caches otimizados
- Prefetch
- EDNS 1232
- ACL automática (conforme informações informadas)
- RPZ configurável
- Logrotate
- THP desabilitado

### 🟠 Monitoramento
- Zabbix Sender opcional
- Scripts de falhas e retomada
- Notificações Telegram (opcional, via `telegram-notify` configurado por você)

---

## 🔐 Segurança

- Ajustes de memória e conntrack
- ACL obrigatória
- IPv6 totalmente suportado
- Deny ANY
- Cache seguro

---

## 📜 Licença

Este projeto está licenciado sob os termos da **MIT License**.  
Veja o arquivo `LICENSE` para mais detalhes.

---

## 💬 Contato

Autor: **LAILSON ARAUJO**  
WhatsApp: **+55 83 98615-2503**

Contribuições são bem-vindas! Sinta-se à vontade para abrir Issues ou Pull Requests.
