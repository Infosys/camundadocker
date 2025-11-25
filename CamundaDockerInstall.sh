#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name:     CamundaDockerInstall.sh
# Description:     Cloud agnostic solution for Camunda docker install, which will Pull Camunda image and will deploy into VM.
# Author:          Shivam Bhardwaj
# Reviewer:        Sumit Sahay
# Created:         2025-08-21
# Last Modified:   2025-08-21
# Version:         1.0
# -----------------------------------------------------------------------------
# © 2024-25 Infosys Limited, Bangalore, India. All Rights Reserved.

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
HOST=$(hostname -I | awk '{print $1}')
C8_VERSION="8.7"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/servicelog_${TIMESTAMP}.log"

if [ -e "$LOG_DIR" ] && [ ! -d "$LOG_DIR" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN  : $LOG_DIR exists and is not a directory — moving to ${LOG_DIR}.bak" >&2
  mv -f "$LOG_DIR" "${LOG_DIR}.bak_$(date +%s)" || { echo "Failed to move existing $LOG_DIR" >&2; exit 1; }
fi
mkdir -p "$LOG_DIR"
echo "Camunda 8 Installation Started at $(date) for host $HOST" | tee -a "$LOG_FILE"

# ===========================
# TRACKING & ERROR HANDLING
# ===========================
completed_steps=()
LAST_STEP=""

on_error() {
local exit_code=$?
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Step '$LAST_STEP' failed with exit code $exit_code." | tee -a "$LOG_FILE"
    rollback
}
trap on_error ERR

rollback() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Installation failed. Starting rollback..." | tee -a "$LOG_FILE"

    for (( idx=${#completed_steps[@]}-1; idx>=0; idx-- )); do
        step="${completed_steps[idx]}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] START : Rollback $step" | tee -a "$LOG_FILE"

        case "$step" in
            "install_required_tools")
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Cannot uninstall system tools. Skipping..." | tee -a "$LOG_FILE"
                ;;
            "install_docker")
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : Removing Docker packages..." | tee -a "$LOG_FILE"
                sudo systemctl stop docker docker.socket 2>/dev/null
                sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker \
                    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Docker package purge failed" | tee -a "$LOG_FILE"
                sudo apt-get autoremove -y || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING : Autoremove failed" | tee -a "$LOG_FILE"
                sudo rm -rf /var/lib/docker /var/lib/containerd || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING : Failed to remove Docker directories" | tee -a "$LOG_FILE"
                sudo groupdel docker 2>/dev/null
                ;;
            "install_docker_compose")
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : Removing Docker Compose..." | tee -a "$LOG_FILE"
                sudo apt-get remove -y docker-compose-plugin || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Docker Compose plugin removal failed" | tee -a "$LOG_FILE"
                sudo rm -f /usr/local/bin/docker-compose || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING : Standalone Docker Compose binary not found or already removed" | tee -a "$LOG_FILE"
                ;;
            "elasticsearch_config")
                sudo rm -f /etc/sysctl.d/99-elasticsearch.conf || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Elasticsearch config removal failed" | tee -a "$LOG_FILE"
                sudo sysctl --system || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Sysctl reload failed" | tee -a "$LOG_FILE"
                ;;
            "download_camunda_compose")
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : Cleaning up Camunda Docker resources and files..." | tee -a "$LOG_FILE"
                docker rm -f $(docker ps -aq) 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : No containers to remove." | tee -a "$LOG_FILE"
                docker rmi -f $(docker images -q) 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : No images to remove." | tee -a "$LOG_FILE"
                docker volume rm -f $(docker volume ls -q) 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : No volumes to remove." | tee -a "$LOG_FILE"
                rm -rf "$SCRIPT_DIR/camunda-compose" || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Camunda bundle removal failed" | tee -a "$LOG_FILE"
                ;;
            "configure_env")
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO : Skipping environment rollback." | tee -a "$LOG_FILE"
                ;;
            "start_camunda_stack"|"health_check")
                cd ~/camunda-compose && docker compose down || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Camunda stack shutdown failed" | tee -a "$LOG_FILE"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Unknown rollback step: $step" | tee -a "$LOG_FILE"
                ;;
            *)
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Unknown rollback step: $step" | tee -a "$LOG_FILE"
                ;;
        esac
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] END : Rollback complete." | tee -a "$LOG_FILE"
    exit 1
}

# ===============================
# UTILS
# ===============================
apt_install_noninteractive() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >> "$LOG_FILE" 2>&1
}

# ===============================
# STEP 0 – Install Required Tools
# ===============================
install_required_tools() {
    LAST_STEP="install_required_tools"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 0: Checking required tools..." | tee -a "$LOG_FILE"

    required_tools=("curl" "unzip" "tee" "nano" "tar" "yq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : $tool not found. Attempting installation..." | tee -a "$LOG_FILE"
            sudo apt-get install -y "$tool" >> "$LOG_FILE" 2>&1

            if command -v "$tool" &> /dev/null; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $tool installed successfully." | tee -a "$LOG_FILE"
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : $tool installation failed." | tee -a "$LOG_FILE"
                rollback
                exit 1
            fi
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] END : $tool is already installed." | tee -a "$LOG_FILE"
        fi
    done
    completed_steps+=("install_required_tools")
}

# ===========================
# STEP 1 – Install Docker
# ===========================
install_docker() {
    LAST_STEP="install_docker"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 1: Checking Docker..." | tee -a "$LOG_FILE"

    if ! command -v docker &> /dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : Docker not found. Installing..." | tee -a "$LOG_FILE"
        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo rm -f /etc/apt/keyrings/docker.gpg

        sudo apt-get update -y >>"$LOG_FILE" 2>&1
        sudo apt-get install -y ca-certificates curl gnupg lsb-release >>"$LOG_FILE" 2>&1

        sudo mkdir -p /etc/apt/keyrings
        sudo chmod 755 /etc/apt/keyrings

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update -y >>"$LOG_FILE" 2>&1
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >>"$LOG_FILE" 2>&1

        sudo systemctl enable --now docker >>"$LOG_FILE" 2>&1

        CURRENT_USER=$(whoami)
        sudo usermod -aG docker "$CURRENT_USER" >> "$LOG_FILE" 2>&1

        if command -v docker &> /dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Docker installed successfully." | tee -a "$LOG_FILE"
            docker --version | tee -a "$LOG_FILE"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Docker installation failed." | tee -a "$LOG_FILE"
            rollback
            exit 1
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK : Docker is already installed." | tee -a "$LOG_FILE"
        docker --version | tee -a "$LOG_FILE"
    fi
    completed_steps+=("install_docker")
    LAST_STEP=""
}

# ===============================
# STEP 2 – Install Docker Compose
# ===============================
install_docker_compose() {
    LAST_STEP="install_docker_compose"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 2: Checking Docker Compose..." | tee -a "$LOG_FILE"

    if ! docker compose version &> /dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : Docker Compose not found. Installing..." | tee -a "$LOG_FILE"
        sudo apt-get install -y docker-compose-plugin >> "$LOG_FILE" 2>&1
        if docker compose version &> /dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Docker Compose installed successfully." | tee -a "$LOG_FILE"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Docker Compose installation failed." | tee -a "$LOG_FILE"
            rollback
            exit 1
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK     : Docker Compose is already installed." | tee -a "$LOG_FILE"
    fi

    docker compose version | tee -a "$LOG_FILE"
    completed_steps+=("install_docker_compose")
    LAST_STEP=""
}

# ===========================
# STEP 3 – Configure Elasticsearch
# ===========================
configure_elasticsearch() {
    LAST_STEP="configure_elasticsearch"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 3: Configuring Elasticsearch..." | tee -a "$LOG_FILE"

    if ! grep -q "vm.max_map_count=262144" /etc/sysctl.d/99-elasticsearch.conf 2>/dev/null; then
        echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
        sudo sysctl --system >> "$LOG_FILE" 2>&1
        if [[ $? -eq 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Elasticsearch kernel config updated." | tee -a "$LOG_FILE"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR : Failed to apply sysctl settings." | tee -a "$LOG_FILE"
            rollback
            exit 1
        fi
    else
        echo "Elasticsearch kernel config already set." | tee -a "$LOG_FILE"
    fi

    completed_steps+=("configure_elasticsearch")
    LAST_STEP=""
}

# ==============================
# STEP 4 – Download Camunda Bundle
# ==============================
download_camunda_compose() {
    LAST_STEP="download_camunda_compose"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 4: Downloading Camunda bundle..." | tee -a "$LOG_FILE"
    mkdir -p ./camunda-compose || {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Failed to create camunda-compose directory." | tee -a "$LOG_FILE"
        rollback
        exit 1
    }
    BUNDLE_ZIP="docker-compose-${C8_VERSION}.zip"
    BUNDLE_URL="https://github.com/camunda/camunda-distributions/releases/download/docker-compose-${C8_VERSION}/${BUNDLE_ZIP}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : Downloading from $BUNDLE_URL" | tee -a "$LOG_FILE"
    if ! curl -L -o "./camunda-compose/$BUNDLE_ZIP" "$BUNDLE_URL" >> "$LOG_FILE" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Failed to download Camunda bundle." | tee -a "$LOG_FILE"
        rollback
        exit 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : Extracting Camunda compose..." | tee -a "$LOG_FILE"
    if unzip -o "./camunda-compose/$BUNDLE_ZIP" -d ./camunda-compose >> "$LOG_FILE" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Camunda compose downloaded and extracted." | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Extraction failed." | tee -a "$LOG_FILE"
        rollback
        exit 1
    fi
    completed_steps+=("download_camunda_compose")
    LAST_STEP=""
}

# ==============================
# STEP 5 – Configure .env and docker-compose.yaml
# ==============================
configure_env() {
    LAST_STEP="configure_env"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 5: Configuring environment variables..." | tee -a "$LOG_FILE"

    ENV_FILE="$SCRIPT_DIR/camunda-compose/.env"
    COMPOSE_FILE="$SCRIPT_DIR/camunda-compose/docker-compose.yaml"

    if [ -f "$ENV_FILE" ]; then
        sed -i "s/^HOST=.*/HOST=${HOST}/" "$ENV_FILE"
        sed -i "s/^KEYCLOAK_HOST=.*/KEYCLOAK_HOST=${HOST}/" "$ENV_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : .env updated with HOST=${HOST}" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : .env file not found at $ENV_FILE." | tee -a "$LOG_FILE"
        rollback
        exit 1
    fi
    if [ -f "$COMPOSE_FILE" ]; then
        yq e '.services.keycloak.environment.KC_BOOTSTRAP_ADMIN_USERNAME = "admin" |
      .services.keycloak.environment.KC_BOOTSTRAP_ADMIN_PASSWORD = "admin"' -i "$COMPOSE_FILE"
        yq e '.services.web-modeler-restapi.environment.RESTAPI_SERVER_URL = "http://${HOST}:8070" |
      .services.web-modeler-webapp.environment.SERVER_URL = "http://${HOST}:8070" |
      .services.web-modeler-webapp.environment.CLIENT_PUSHER_HOST = "${HOST}"' -i "$COMPOSE_FILE"
        sed -i '/^[[:space:]]*image: camunda\/web-modeler-restapi:${CAMUNDA_WEB_MODELER_VERSION}/a\
    command: /bin/sh -c "java $JAVA_OPTIONS org.springframework.boot.loader.JarLauncher"' "$COMPOSE_FILE"
        else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : docker-compose.yaml not found at $COMPOSE_FILE." | tee -a "$LOG_FILE"
        rollback
        exit 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: .env and docker-compose.yaml configured." | tee -a "$LOG_FILE"
    completed_steps+=("configure_env")
    LAST_STEP=""
}

# ==============================
# STEP 6 – Start Camunda Stack
# =============================
start_camunda_stack() {
    LAST_STEP="start_camunda_stack"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 6: Starting Camunda stack..." | tee -a "$LOG_FILE"
    COMPOSE_DIR="$SCRIPT_DIR/camunda-compose"
    COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yaml"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO  : Using COMPOSE_DIR=$COMPOSE_DIR" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO   : Starting Camunda containers..." | tee -a "$LOG_FILE"
      if cd "$COMPOSE_DIR" && docker compose up -d; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Camunda stack started successfully." | tee -a "$LOG_FILE"
        completed_steps+=("start_camunda_stack")
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Failed to start Camunda stack. Check logs at $LOG_FILE for details." | tee -a "$LOG_FILE"
        rollback
        exit 1
    fi
    LAST_STEP=""
}

# =======================================
# STEP 7 - Health Check (External Script)
# =======================================
health_check() {
    LAST_STEP="health_check"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 7: Running Health Check..." | tee -a "$LOG_FILE"
    echo "SCRIPT_DIR resolved to: $SCRIPT_DIR" | tee -a "$LOG_FILE"
    HEALTH_SCRIPT="$SCRIPT_DIR/camunda-health-check.sh"

    if [ -x "$HEALTH_SCRIPT" ]; then
        "$HEALTH_SCRIPT" "$HOST" || echo "Health check script exited with failure, continuing for diagnostics..." | tee -a "$LOG_FILE"
        completed_steps+=("health_check")
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR  : Health check script not found or not executable at $HEALTH_SCRIPT." | tee -a "$LOG_FILE"
        rollback "health_check"
    fi
    completed_steps+=("health_check")
    LAST_STEP=""
}

#============================
# Called Main Function
#============================
main(){
install_required_tools
install_docker
install_docker_compose
configure_elasticsearch
download_camunda_compose
configure_env
start_camunda_stack
health_check
}
main

# ==============================
# FINISH
# =============================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALL DONE: Installation finished. Step completed: ${completed_steps[*]}" | tee -a "$LOG_FILE"