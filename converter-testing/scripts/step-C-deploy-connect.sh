#!/bin/bash

# Step C: Deploy Kafka Connect with Apicurio Registry Converter Plugin
# This script builds and deploys a custom Kafka Connect image that includes
# the Apicurio Registry converter distribution.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

COMPOSE_FILE="$PROJECT_DIR/docker-compose-connect.yml"

init_log "step-C-deploy-connect.log"

log "================================================================"
log "  Step C: Deploy Kafka Connect"
log "================================================================"
log ""

# Step 1: Build custom Connect image
log "[1/4] Building Kafka Connect image with Apicurio converter..."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" build connect 2>&1 | tee -a "$LOG_FILE"
log ""

# Step 2: Create data directory for connectors inside the Connect container
log "[2/4] Starting Kafka Connect..."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d connect 2>&1 | tee -a "$LOG_FILE"
log ""

# Step 3: Wait for Connect to be ready
log "[3/4] Waiting for Kafka Connect to be ready..."
if ! wait_for_url "$CONNECT_URL/" 120 3; then
    log ""
    log "Failed to start Kafka Connect. Check logs:"
    log "  docker logs converter-connect"
    exit 1
fi
log ""

# Step 4: Verify Connect and list available plugins
log "[4/4] Verifying Kafka Connect and available plugins..."
CONNECT_INFO=$(curl -s "$CONNECT_URL/")
log "Connect Worker Info:"
log "  $CONNECT_INFO"
log ""

log "Available connector plugins:"
curl -s "$CONNECT_URL/connector-plugins" | jq -r '.[].class' 2>/dev/null | tee -a "$LOG_FILE"
log ""

# Check if Apicurio converter classes are available
log "Checking Apicurio converter availability..."
PLUGINS=$(curl -s "$CONNECT_URL/connector-plugins")
log "  Connector plugins loaded: $(echo "$PLUGINS" | jq length)"
log ""

# Verify converter JARs are present
log "Verifying converter JARs in plugin path..."
docker exec converter-connect ls -la /opt/kafka/connect-plugins/apicurio-converter/ 2>&1 | tee -a "$LOG_FILE"
log ""

# Prepare data directory
log "Preparing data directory..."
docker exec converter-connect mkdir -p /data
docker exec converter-connect sh -c 'touch /data/avro-source-input.txt /data/json-source-input.txt'
log ""

# Collect container logs
docker logs converter-connect > "$CONTAINER_LOG_DIR/connect-initial.log" 2>&1

log "================================================================"
log "  Step C completed successfully"
log "================================================================"
log ""
log "Kafka Connect is running at: $CONNECT_URL"
log "Plugin path: /opt/kafka/connect-plugins"
log "Logs saved to: $LOG_FILE"
log ""
