#!/bin/bash
set -e

# ================================
#      Bifrost Installer
# ================================

# --- Cores ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m' # Sem cor

function info() { echo -e "${BLUE}[INFO]${NC} $1"; }
function ok() { echo -e "${GREEN}[OK]${NC} $1"; }
function warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
function error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

echo -e "${GREEN}========================================"
echo -e "             Bifrost Installer"
echo -e "========================================${NC}"

# --- Atualização do sistema ---
info "Atualizando pacotes do sistema..."
sudo apt update -y && sudo apt upgrade -y

# --- Instalação do Docker e dependências ---
info "Instalando Docker, Compose, Git e Python..."
curl -fsSL https://get.docker.com | sh
sudo apt install -y docker-compose-plugin git python3-pip
sudo usermod -aG docker $USER

# --- Estrutura de pastas ---
info "Criando estrutura de pastas..."
BASE_DIR="$HOME/bifrost"
DOCKER_DIR="$BASE_DIR/docker"
mkdir -p "$DOCKER_DIR/mqtt-broker" "$DOCKER_DIR/mqtt-explorer"

# --- Clonando repositórios ---
info "Clonando repositórios..."
cd "$BASE_DIR"
[ ! -d "dispatcher" ] && git clone https://github.com/the-bifrost/dispatcher.git || warn "dispatcher já existe, pulando."
[ ! -d "dashboard" ] && git clone https://github.com/the-bifrost/dashboard.git || warn "dashboard já existe, pulando."

# --- Dependências Python ---
info "Instalando bibliotecas Python..."
if [ -f "$BASE_DIR/dispatcher/requirements.txt" ]; then
    pip3 install --break-system-packages -r "$BASE_DIR/dispatcher/requirements.txt"
else
    warn "Arquivo requirements.txt não encontrado no dispatcher. Criando..."
    cat <<EOF > "$BASE_DIR/dispatcher/requirements.txt"
paho-mqtt
flask
flask-socketio
EOF
    pip3 install -r "$BASE_DIR/dispatcher/requirements.txt"
fi

# --- Mosquitto ---
info "Configurando Mosquitto Broker..."
cat <<EOF > "$DOCKER_DIR/mqtt-broker/docker-compose.yml"
services:
  mosquitto:
    image: eclipse-mosquitto:latest
    container_name: mosquitto_broker
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
      - ./data:/mosquitto/data
      - ./log:/mosquitto/log
EOF
echo -e "listener 1883\nallow_anonymous true" > "$DOCKER_DIR/mqtt-broker/mosquitto.conf"

# --- MQTT Explorer ---
info "Configurando MQTT Explorer..."
cat <<EOF > "$DOCKER_DIR/mqtt-explorer/docker-compose.yml"
services:
  mqtt-explorer:
    container_name: mqtt-explorer
    image: smeagolworms4/mqtt-explorer
    hostname: mqtt-explorer
    restart: always
    ports:
      - "9002:9001"
    environment:
      - HTTP_PORT=9001
      - CONFIG_PATH=/mqtt-explorer/config
      - TZ=America/Sao_Paulo
    volumes:
      - ./config:/mqtt-explorer/config
      - /etc/timezone:/etc/timezone:ro
EOF

# --- UARTs ---
info "Habilitando e liberando UARTs..."
sudo sed -i 's/console=serial0,[0-9]* //g' /boot/firmware/cmdline.txt || true
sudo sed -i 's/console=ttyAMA0,[0-9]* //g' /boot/firmware/cmdline.txt || true
sudo sed -i 's/console=tty[0-9]\+ //g' /boot/firmware/cmdline.txt || true
sudo sed -i '1s/^/console=tty1 /' /boot/firmware/cmdline.txt

sudo tee -a /boot/firmware/config.txt > /dev/null <<EOL
enable_uart=1
dtoverlay=disable-bt
dtoverlay=uart1
dtoverlay=uart2
dtoverlay=uart3
dtoverlay=uart4
dtoverlay=uart5
EOL

# --- Subindo containers ---
info "Subindo containers..."
cd "$DOCKER_DIR/mqtt-broker" && sudo docker compose up -d
cd "$DOCKER_DIR/mqtt-explorer" && sudo docker compose up -d

# --- Finalização ---
ok "Instalação concluída!"
warn "Reinicie o sistema para aplicar mudanças na UART."
echo -e "${GREEN}Após reiniciar, os serviços podem ser gerenciados com:${NC}"
echo "  cd ~/bifrost/docker/mqtt-broker && docker compose up -d"
echo "  cd ~/bifrost/docker/mqtt-explorer && docker compose up -d"
echo
info "Reiniciando sistema..."
sudo reboot
