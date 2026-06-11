#!/bin/bash

# Common utility functions for converter test scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ENV_FILE:-$PROJECT_DIR/.env}"
LOG_DIR="$PROJECT_DIR/logs"
CONTAINER_LOG_DIR="$LOG_DIR/containers"
DATA_DIR="$PROJECT_DIR/data"
CONNECTORS_DIR="$PROJECT_DIR/connectors"

CONNECT_URL="http://localhost:8083"
REGISTRY_URL="http://localhost:8080"
REGISTRY_MGMT_URL="http://localhost:9000"
REGISTRY_API="$REGISTRY_URL/apis/registry/v3"
REGISTRY_HEALTH_URL="$REGISTRY_MGMT_URL/q/health/ready"

mkdir -p "$LOG_DIR"
mkdir -p "$CONTAINER_LOG_DIR"
mkdir -p "$DATA_DIR"

init_log() {
    LOG_FILE="$LOG_DIR/$1"
}

log() {
    echo "$1" | tee -a "$LOG_FILE"
}

wait_for_url() {
    local url=$1
    local timeout=${2:-60}
    local interval=${3:-2}
    local elapsed=0

    log "Waiting for $url to be healthy (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            log "Health check passed after ${elapsed}s"
            return 0
        fi
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log ""
    log "Health check failed after ${timeout}s"
    return 1
}

wait_for_kafka() {
    local timeout=${1:-90}
    local interval=2
    local elapsed=0

    log "Waiting for Kafka broker to be ready (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec converter-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1; then
            log "Kafka broker is ready after ${elapsed}s"
            return 0
        fi
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log ""
    log "Kafka broker failed to start after ${timeout}s"
    return 1
}

wait_for_sink_output() {
    local file=$1
    local timeout=${2:-30}
    local interval=2
    local elapsed=0

    log "Waiting for sink output in $file (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec converter-connect test -s "$file" 2>/dev/null; then
            log "Sink output detected after ${elapsed}s"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log "No sink output after ${timeout}s"
    return 1
}

wait_for_connector_running() {
    local connector_name=$1
    local timeout=${2:-30}
    local interval=2
    local elapsed=0

    log "Waiting for connector $connector_name to be RUNNING (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        local state
        state=$(curl -s "$CONNECT_URL/connectors/$connector_name/status" | jq -r '.connector.state' 2>/dev/null)
        local task_state
        task_state=$(curl -s "$CONNECT_URL/connectors/$connector_name/status" | jq -r '.tasks[0].state // "UNKNOWN"' 2>/dev/null)
        if [ "$state" = "RUNNING" ] && [ "$task_state" = "RUNNING" ]; then
            log "Connector $connector_name is RUNNING after ${elapsed}s"
            return 0
        fi
        if [ "$task_state" = "FAILED" ]; then
            log "Connector $connector_name task FAILED after ${elapsed}s"
            return 1
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log "Connector $connector_name not RUNNING after ${timeout}s"
    return 1
}

create_connector() {
    local config_file=$1
    local connector_name=$2

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d @"$config_file" \
        "$CONNECT_URL/connectors")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | head -n -1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "  Connector $connector_name created successfully (HTTP $http_code)"
        return 0
    elif [ "$http_code" = "409" ]; then
        log "  Connector $connector_name already exists, deleting and recreating..."
        curl -s -X DELETE "$CONNECT_URL/connectors/$connector_name" > /dev/null 2>&1
        sleep 2
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d @"$config_file" \
            "$CONNECT_URL/connectors")
        http_code=$(echo "$response" | tail -1)
        if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
            log "  Connector $connector_name recreated successfully"
            return 0
        fi
    fi

    log "  Failed to create connector $connector_name (HTTP $http_code)"
    log "  Response: $body"
    return 1
}
