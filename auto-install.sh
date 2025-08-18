#!/bin/bash
set -e

# ================================
# Instalador do Projeto Bifrost
# ================================

# --- Cores ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m'

function info() { echo -e "${BLUE}[INFO]${NC} $1"; }
function ok() { echo -e "${GREEN}[OK]${NC} $1"; }
function warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
function error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

echo -e "${GREEN}========================================"
echo -e "      INSTALADOR DO PROJETO BIFROST"
echo -e "========================================${NC}"

# --- Atualização do sistema ---
info "Atualizando pacotes..."
sudo apt update -y && sudo apt upgrade -y

# --- Docker ---
if ! command -v docker &>/dev/null; then
    info "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
else
    ok "Docker já está instalado."
fi

# --- Docker Compose ---
if ! command -v docker compose &>/dev/null; then
    info "Instalando Docker Compose plugin..."
    sudo apt install -y docker-compose-plugin
else
    ok "Docker Compose já está instalado."
fi

# --- Git ---
if ! command -v git &>/dev/null; then
    info "Instalando Git..."
    sudo apt install -y git
else
    ok "Git já está instalado."
fi

# --- Python ---
if ! command -v python3 &>/dev/null; then
    info "Instalando Python..."
    sudo apt install -y python3 python3-pip python3-venv
else
    ok "Python já está instalado."
    if ! command -v pip3 &>/dev/null; then
        info "Instalando pip3..."
        sudo apt install -y python3-pip
    else
        ok "pip3 já está instalado."
    fi
fi

# --- Estrutura de pastas ---
BASE_DIR="$HOME/bifrost"
DOCKER_DIR="$BASE_DIR/docker"
mkdir -p "$DOCKER_DIR/mqtt-broker" "$DOCKER_DIR/mqtt-explorer"

# --- Clonando repositórios ---
cd "$BASE_DIR"
[ ! -d "dispatcher" ] && git clone https://github.com/the-bifrost/dispatcher.git || ok "dispatcher já existe."
[ ! -d "dashboard" ] && git clone https://github.com/the-bifrost/dashboard.git || ok "dashboard já existe."

# --- Dependências Python ---
if [ -f "$BASE_DIR/dispatcher/requirements.txt" ]; then
    info "Instalando bibliotecas Python..."
    pip3 install --break-system-packages -r "$BASE_DIR/dispatcher/requirements.txt"
fi

# --- Mosquitto ---
if [ ! -f "$DOCKER_DIR/mqtt-broker/docker-compose.yml" ]; then
    info "Criando configuração do Mosquitto..."
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
else
    ok "Configuração do Mosquitto já existe."
fi

# --- MQTT Explorer ---
if [ ! -f "$DOCKER_DIR/mqtt-explorer/docker-compose.yml" ]; then
    info "Criando configuração do MQTT Explorer..."
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
else
    ok "Configuração do MQTT Explorer já existe."
fi
# --- Monitoring (Grafana, Prometheus, Node Exporter) ---
MONITORING_DIR="$DOCKER_DIR/monitoring"
GRAFANA_DIR="$MONITORING_DIR/grafana"
PROMETHEUS_DIR="$MONITORING_DIR/prometheus"

if [ ! -f "$MONITORING_DIR/compose.yaml" ]; then
    info "Criando estrutura de monitoring..."
    mkdir -p "$GRAFANA_DIR" "$PROMETHEUS_DIR"

    # compose.yaml
    cat <<'EOF' > "$MONITORING_DIR/compose.yaml"
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - 9100:9100

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yaml'
    ports:
      - 9090:9090
    restart: unless-stopped
    volumes:
      - ./prometheus:/etc/prometheus
      - prom_data:/prometheus
    extra_hosts:
      - "host.docker.internal:host-gateway"

  grafana:
    image: grafana/grafana
    container_name: grafana
    ports:
      - 3000:3000
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=grafana
      - GF_INSTALL_PLUGINS=mqtt
    volumes:
      - ./grafana:/etc/grafana/provisioning/datasources

volumes:
  prom_data:
EOF

    # datasource.yaml
    cat <<'EOF' > "$GRAFANA_DIR/datasource.yaml"
apiVersion: 1

datasources:
- name: Prometheus
  type: prometheus
  url: http://prometheus:9090 
  isDefault: true
  access: proxy
  editable: true
- name: MQTT
  type: grafana-mqtt-datasource
  access: proxy
  url: mqtt://bifrost.local:1883
  jsonData:
    tlsSkipVerify: true
    timeField: time
EOF

    # prometheus.yaml
    cat <<'EOF' > "$PROMETHEUS_DIR/prometheus.yaml"
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
alerting:
  alertmanagers:
  - static_configs:
    - targets: []
    scheme: http
    timeout: 10s
    api_version: v2
scrape_configs:
  - job_name: prometheus
    honor_timestamps: true
    scrape_interval: 15s
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: http
    static_configs:
    - targets:
      - localhost:9090
  - job_name: node
    static_configs:
    - targets:
      - host.docker.internal:9100
EOF
else
    ok "Configuração de monitoring já existe."
fi

# --- Monitoring Script (MQTT Publisher) ---
MONITORING_PY="$MONITORING_DIR/monitoring.py"
if [ ! -f "$MONITORING_PY" ]; then
    info "Criando script de monitoring MQTT..."
    cat <<'EOF' > "$MONITORING_PY"
import paho.mqtt.client as mqtt
import psutil
import time
import os

# Configuração do MQTT
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_BASE_TOPIC = "/monitoring/"

def get_cpu_temp():
    try:
        res = os.popen("vcgencmd measure_temp").readline()
        temp_str = res.replace("temp=", "").replace("'C\n", "")
        return float(temp_str)
    except:
        return None

def get_uptime():
    uptime_seconds = time.time() - psutil.boot_time()
    days = int(uptime_seconds // 86400)
    hours = int((uptime_seconds % 86400) // 3600)
    minutes = int((uptime_seconds % 3600) // 60)
    return f"{days}d {hours}h {minutes}m"

client = mqtt.Client()
client.connect(MQTT_BROKER, MQTT_PORT, 60)

print("📡 Publicando dados do Raspberry Pi em tópicos MQTT separados...")

try:
    while True:
        cpu_temp = get_cpu_temp()
        cpu_usage = psutil.cpu_percent(interval=1)
        ram_usage = psutil.virtual_memory().percent
        uptime = get_uptime()

        client.publish(MQTT_BASE_TOPIC + "cpu_temp", cpu_temp)
        client.publish(MQTT_BASE_TOPIC + "cpu_usage", cpu_usage)
        client.publish(MQTT_BASE_TOPIC + "ram_usage", ram_usage)
        client.publish(MQTT_BASE_TOPIC + "uptime", uptime)

        print(f"cpu_temp → {cpu_temp} °C")
        print(f"cpu_usage → {cpu_usage} %")
        print(f"ram_usage → {ram_usage} %")
        print(f"uptime → {uptime}")
        print("-" * 40)

        time.sleep(1)

except KeyboardInterrupt:
    print("\n🛑 Encerrando...")
    client.disconnect()
EOF
else
    ok "Script de monitoring já existe."
fi

# --- Service do Monitoring ---
SERVICE_FILE="/etc/systemd/system/monitoring.service"
if [ ! -f "$SERVICE_FILE" ]; then
    info "Criando serviço systemd para o Monitoring..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Monitoring Service
After=network.target mosquitto.service

[Service]
User=$USER
WorkingDirectory=$MONITORING_DIR
ExecStart=python3 monitoring.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable monitoring
    sudo systemctl start monitoring
else
    ok "Serviço monitoring já existe."
fi

# --- UARTs ---
UARTS=(
    "enable_uart=1"
    "dtoverlay=disable-bt"
    "dtoverlay=uart1"
    "dtoverlay=uart2"
    "dtoverlay=uart3"
    "dtoverlay=uart4"
    "dtoverlay=uart5"
)
CONFIG_FILE="/boot/firmware/config.txt"
for uart in "${UARTS[@]}"; do
    if ! grep -Fxq "$uart" "$CONFIG_FILE"; then
        echo "$uart" | sudo tee -a "$CONFIG_FILE" > /dev/null
        ok "Adicionado: $uart"
    else
        ok "Já existe: $uart"
    fi
done

# --- Service do Dispatcher ---
SERVICE_FILE="/etc/systemd/system/dispatcher.service"
if [ ! -f "$SERVICE_FILE" ]; then
    info "Criando serviço systemd para o Dispatcher..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Dispatcher Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$BASE_DIR/dispatcher
ExecStart=/usr/bin/python3 main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable dispatcher
else
    ok "Serviço dispatcher já existe."
fi

# --- Comando dispatcher ---
if [ ! -f "/usr/local/bin/dispatcher" ]; then
    info "Criando comando 'dispatcher'..."
    sudo tee /usr/local/bin/dispatcher > /dev/null <<'EOF'
#!/bin/bash
case "$1" in
    start) sudo systemctl start dispatcher ;;
    stop) sudo systemctl stop dispatcher ;;
    restart) sudo systemctl restart dispatcher ;;
    status) sudo systemctl status dispatcher ;;
    *) echo "Uso: dispatcher {start|stop|restart|status}" && exit 1 ;;
esac
EOF
    sudo chmod +x /usr/local/bin/dispatcher
else
    ok "Comando dispatcher já existe."
fi

# --- Subindo containers ---
info "Subindo containers..."
(cd "$MONITORING_DIR" && sudo docker compose up -d)
(cd "$DOCKER_DIR/mqtt-broker" && sudo docker compose up -d)
(cd "$DOCKER_DIR/mqtt-explorer" && sudo docker compose up -d)

ok "Instalação concluída!"
info "Reiniciando o sistema...."
sudo reboot
