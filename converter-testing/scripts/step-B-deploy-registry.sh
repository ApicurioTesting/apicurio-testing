#!/bin/bash

# Step B: Deploy Apicurio Registry
# This script deploys Apicurio Registry in in-memory (H2) mode

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

COMPOSE_FILE="$PROJECT_DIR/docker-compose-registry.yml"

init_log "step-B-deploy-registry.log"

log "================================================================"
log "  Step B: Deploy Apicurio Registry"
log "================================================================"
log ""

# Step 1: Start Registry
log "[1/3] Starting Apicurio Registry (in-memory mode)..."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
log ""

# Step 2: Wait for Registry to be ready
log "[2/3] Waiting for Registry to be ready..."
if ! wait_for_url "$REGISTRY_HEALTH_URL" 60; then
    log ""
    log "Failed to start Registry. Check logs:"
    log "  docker logs converter-registry"
    exit 1
fi
log ""

# Step 3: Verify Registry
log "[3/3] Verifying Registry..."
SYSTEM_INFO=$(curl -s http://localhost:8080/apis/registry/v3/system/info)
log "Registry System Info:"
log "  $SYSTEM_INFO"
log ""

# Collect container logs
docker logs converter-registry > "$CONTAINER_LOG_DIR/registry-initial.log" 2>&1

log "================================================================"
log "  Step B completed successfully"
log "================================================================"
log ""
log "Apicurio Registry is running at: http://localhost:8080"
log "API v3 URL: http://localhost:8080/apis/registry/v3"
log "Logs saved to: $LOG_FILE"
log ""
