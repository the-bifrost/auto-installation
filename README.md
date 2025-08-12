# 🚀 Bifrost Auto-Install

Este repositório contém o script de instalação automática do **Projeto Bifrost**, configurando todos os serviços necessários (Docker, MQTT Broker, MQTT Explorer, dispatcher, dashboard, dependências Python, UARTs, etc.) de forma simples e rápida no seu Raspberry Pi.

---

## 📦 O que este script faz

- Atualiza o sistema
- Instala **Docker** e **docker-compose-plugin**
- Instala **Git**, **Python 3**, **pip3** e **venv**
- Clona os repositórios `dispatcher` e `dashboard`
- Instala dependências Python
- Configura **Mosquitto MQTT Broker**
- Configura **MQTT Explorer**
- Habilita e libera UARTs no Raspberry Pi
- Cria **service** para rodar o `dispatcher` automaticamente
- Cria **atalhos** para iniciar, parar e reiniciar o dispatcher (`dispatcher start`, `dispatcher stop`, `dispatcher restart`)

---

## ⚙️ Como usar

No seu Raspberry Pi, execute:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/the-bifrost/auto-installation/main/auto-install.sh)"
