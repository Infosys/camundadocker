#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name:     CamundaHealthCheck.sh
# Description:     Unified Health Check Script for Camunda 8 Self-Managed (Docker Compose)
# Author:          Shivam Bhardwaj
# Reviewer:        Sumit Sahay
# Created:         2025-08-21
# Last Modified:   2025-08-21
# Version:         1.0
# -----------------------------------------------------------------------------
# © 2024-25 Infosys Limited, Bangalore, India. All Rights Reserved.

set -euo pipefail

#=====================
# Setup logging
#=====================
HOST=$(hostname -I | awk '{print $1}')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/health_${TIMESTAMP}.log"
mkdir -p "$LOG_DIR"


echo "Camunda 8 Health Check Started at $(date)" | tee -a "$LOG_FILE"

#=====================
# Services
#=====================
services_docker=("zeebe" "operate" "tasklist" "optimize" "identity" "keycloak" "connectors" "elasticsearch" "web-modeler-restapi" "web-modeler-webapp" "web-modeler-db")
declare -A services_http=(
  ["Operate"]=8081
  ["Tasklist"]=8082
  ["Optimize"]=8083
  ["Identity"]=8084
  ["Keycloak"]=18080
  ["Elasticsearch"]=9200
)

failure_detected=0

#========================
# Docker Compose Status
#========================
echo -e "\nDocker Compose Services Status:" | tee -a "$LOG_FILE"
docker compose ps | tee -a "$LOG_FILE"

#========================
# Docker Images
#========================
echo -e "\nDocker Images:" | tee -a "$LOG_FILE"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | tee -a "$LOG_FILE"

#========================
# Docker container health
#========================
echo -e "\nContainer Health Checks:" | tee -a "$LOG_FILE"
for service in "${services_docker[@]}"; do
    container_id=$(docker compose ps -q "$service")
    if [ -z "$container_id" ]; then
        echo "$service: ❌ Not Found" | tee -a "$LOG_FILE"
        failure_detected=1
        continue
    fi
    status=$(docker inspect --format='{{.State.Status}}' "$container_id")
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "no healthcheck")
    if [ "$status" == "running" ]; then
        if [ "$health" == "healthy" ]; then
            echo "$service: ✅ Running & Healthy" | tee -a "$LOG_FILE"
        elif [ "$health" == "unhealthy" ]; then
            echo "$service: ⚠️ Running but Unhealthy" | tee -a "$LOG_FILE"
            failure_detected=1
        else
            echo "$service: 🟡 Running (No Healthcheck)" | tee -a "$LOG_FILE"
        fi
    else
        echo "$service: ❌ Not Running" | tee -a "$LOG_FILE"
        failure_detected=1
    fi
done

#=====================
# Resource usage
#=====================
echo -e "\nTop 5 Containers by Memory Usage:" | tee -a "$LOG_FILE"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -n 6 | tee -a "$LOG_FILE"

#=====================
# Logs
#=====================
echo -e "\nLast 20 Lines of Each Service Log:" | tee -a "$LOG_FILE"
for service in "${services_docker[@]}"; do
    echo -e "\n--- Logs: $service ---" | tee -a "$LOG_FILE"
    docker compose logs --tail=20 "$service" >> "$LOG_FILE" 2>&1 || echo "No logs found for $service" | tee -a "$LOG_FILE"
done

echo -e "\n===== Camunda 8 Health Check Finished at $(date) =====" | tee -a "$LOG_FILE"

#=====================
# Final status
#=====================
if [ $failure_detected -eq 1 ]; then
    echo "Health check failed: some services are not healthy!" | tee -a "$LOG_FILE" >&2
    exit 1
else
    echo "Health check passed: all services are healthy." | tee -a "$LOG_FILE"
fi