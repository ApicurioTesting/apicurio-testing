#!/bin/bash

# Step A: Deploy Kafka Cluster
# This script deploys Apache Kafka using KRaft mode (no Zookeeper)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

COMPOSE_FILE="$PROJECT_DIR/docker-compose-kafka.yml"

init_log "step-A-deploy-kafka.log"

log "================================================================"
log "  Step A: Deploy Kafka Cluster"
log "================================================================"
log ""

# Step 1: Start Kafka
log "[1/4] Starting Kafka using KRaft mode..."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
log ""

# Step 2: Wait for Kafka to be ready
log "[2/4] Waiting for Kafka broker to be ready..."
if ! wait_for_kafka 90; then
    log ""
    log "Failed to start Kafka. Check logs:"
    log "  docker logs converter-kafka"
    exit 1
fi
log ""

# Step 3: Verify broker
log "[3/4] Verifying Kafka broker..."
docker exec converter-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>&1 | head -n 5 | tee -a "$LOG_FILE"
log ""

# Step 4: Create test topics
log "[4/4] Creating test topics..."
for topic in avro-converter-test json-converter-test; do
    docker exec converter-kafka /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server localhost:9092 \
        --create \
        --topic "$topic" \
        --partitions 1 \
        --replication-factor 1 \
        --if-not-exists 2>&1 | tee -a "$LOG_FILE"
done
log ""

# Verify topics
log "Verifying topics..."
docker exec converter-kafka /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --list 2>&1 | tee -a "$LOG_FILE"
log ""

# Collect container logs
docker logs converter-kafka > "$CONTAINER_LOG_DIR/kafka-initial.log" 2>&1

log "================================================================"
log "  Step A completed successfully"
log "================================================================"
log ""
log "Kafka is running at: localhost:9092"
log "Topics created: avro-converter-test, json-converter-test"
log "Logs saved to: $LOG_FILE"
log ""
