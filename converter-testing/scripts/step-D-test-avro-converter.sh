#!/bin/bash

# Step D: Test Avro Converter
# This script tests the Apicurio Registry Avro converter by:
# 1. Creating a FileStreamSource connector with Avro converter
# 2. Writing test data to the source file
# 3. Creating a FileStreamSink connector with Avro converter
# 4. Verifying data flows through correctly
# 5. Checking schema registration in Apicurio Registry

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

init_log "step-D-test-avro-converter.log"

log "================================================================"
log "  Step D: Test Avro Converter"
log "================================================================"
log ""

# Step 1: Verify prerequisites
log "[1/7] Verifying prerequisites..."
if ! curl -sf "$CONNECT_URL/" > /dev/null 2>&1; then
    log "Kafka Connect is not running. Please run step-C-deploy-connect.sh first."
    exit 1
fi
log "  Kafka Connect is running"

if ! curl -sf "$REGISTRY_HEALTH_URL" > /dev/null 2>&1; then
    log "Apicurio Registry is not running. Please run step-B-deploy-registry.sh first."
    exit 1
fi
log "  Apicurio Registry is running"
log ""

# Step 2: Write test data to source file
log "[2/7] Writing test data to source file..."
TEST_LINES=(
    "Hello from Avro converter test - line 1"
    "Testing serialization with Apicurio Registry - line 2"
    "Kafka Connect converter integration test - line 3"
    "Verifying schema registration works - line 4"
    "Final test message for Avro converter - line 5"
)
SOURCE_LINE_COUNT=${#TEST_LINES[@]}

for line in "${TEST_LINES[@]}"; do
    docker exec converter-connect sh -c "echo '$line' >> /data/avro-source-input.txt"
done
log "  Wrote $SOURCE_LINE_COUNT lines to source file"
log ""

# Step 3: Create source connector with Avro converter
log "[3/7] Creating Avro FileStreamSource connector..."
if ! create_connector "$CONNECTORS_DIR/avro-file-source.json" "avro-file-source"; then
    exit 1
fi
log ""

# Step 4: Wait for source connector to process data
log "[4/7] Waiting for source connector to be running..."
if ! wait_for_connector_running "avro-file-source" 30; then
    SOURCE_STATUS=$(curl -s "$CONNECT_URL/connectors/avro-file-source/status")
    log "  Full status: $SOURCE_STATUS"
fi

SOURCE_STATUS=$(curl -s "$CONNECT_URL/connectors/avro-file-source/status")
SOURCE_STATE=$(echo "$SOURCE_STATUS" | jq -r '.connector.state')
TASK_STATE=$(echo "$SOURCE_STATUS" | jq -r '.tasks[0].state // "UNKNOWN"')
log "  Source connector state: $SOURCE_STATE"
log "  Source task state: $TASK_STATE"
if [ "$TASK_STATE" = "FAILED" ]; then
    TASK_TRACE=$(echo "$SOURCE_STATUS" | jq -r '.tasks[0].trace // "no trace"')
    log "  Task error trace: $TASK_TRACE"
fi
log ""

# Step 5: Create sink connector with Avro converter
log "[5/7] Creating Avro FileStreamSink connector..."
if ! create_connector "$CONNECTORS_DIR/avro-file-sink.json" "avro-file-sink"; then
    exit 1
fi
log ""

# Step 6: Wait and verify sink output
log "[6/7] Waiting for sink connector to consume data..."
wait_for_connector_running "avro-file-sink" 30 || true

SINK_STATUS=$(curl -s "$CONNECT_URL/connectors/avro-file-sink/status")
SINK_STATE=$(echo "$SINK_STATUS" | jq -r '.connector.state')
SINK_TASK_STATE=$(echo "$SINK_STATUS" | jq -r '.tasks[0].state // "UNKNOWN"')
log "  Sink connector state: $SINK_STATE"
log "  Sink task state: $SINK_TASK_STATE"
if [ "$SINK_TASK_STATE" = "FAILED" ]; then
    SINK_TASK_TRACE=$(echo "$SINK_STATUS" | jq -r '.tasks[0].trace // "no trace"')
    log "  Sink task error trace: $SINK_TASK_TRACE"
fi

wait_for_sink_output "/data/avro-sink-output.txt" 30 || true

# Check sink output file
log ""
log "Checking sink output..."
SINK_CONTENT=$(docker exec converter-connect cat /data/avro-sink-output.txt 2>/dev/null || echo "")
if [ -n "$SINK_CONTENT" ]; then
    SINK_LINE_COUNT=$(echo "$SINK_CONTENT" | wc -l | tr -d ' ')
    log "  Sink output has $SINK_LINE_COUNT lines:"
    echo "$SINK_CONTENT" | while IFS= read -r line; do
        log "    $line"
    done

    # Save output for comparison
    echo "$SINK_CONTENT" > "$DATA_DIR/avro-sink-output.txt"
else
    log "  Sink output file is empty or not found"
    log "  This may indicate the converter failed to deserialize the data"
fi
log ""

# Step 7: Verify topic has data
log "[7/7] Verifying Kafka topic..."
TOPIC_OFFSET=$(docker exec converter-kafka /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
    --broker-list localhost:9092 \
    --topic avro-converter-test 2>/dev/null | awk -F: '{sum+=$3} END {print sum+0}')
log "  Messages in avro-converter-test topic: $TOPIC_OFFSET"
log ""

# Report results
AVRO_TEST_PASSED=true
if [ "$SOURCE_STATE" != "RUNNING" ]; then
    AVRO_TEST_PASSED=false
    log "FAIL: Source connector is not running"
fi
if [ "$TASK_STATE" = "FAILED" ]; then
    AVRO_TEST_PASSED=false
    log "FAIL: Source task failed"
fi
if [ "$TOPIC_OFFSET" -eq 0 ]; then
    AVRO_TEST_PASSED=false
    log "FAIL: No messages in topic"
fi
if [ -n "$SINK_CONTENT" ] && [ "$SINK_LINE_COUNT" -ne "$SOURCE_LINE_COUNT" ]; then
    AVRO_TEST_PASSED=false
    log "FAIL: Sink output line count ($SINK_LINE_COUNT) does not match source input ($SOURCE_LINE_COUNT)"
fi

# Collect container logs
docker logs converter-connect > "$CONTAINER_LOG_DIR/connect-after-avro.log" 2>&1

log "================================================================"
if [ "$AVRO_TEST_PASSED" = true ]; then
    log "  Step D completed successfully - Avro Converter PASSED"
else
    log "  Step D completed with issues - check logs above"
fi
log "================================================================"
log ""
log "Connectors status:"
log "  Source: $SOURCE_STATE (task: $TASK_STATE)"
log "  Sink: $SINK_STATE (task: $SINK_TASK_STATE)"
log "  Messages in topic: $TOPIC_OFFSET"
log ""
log "Logs saved to: $LOG_FILE"
log ""

if [ "$AVRO_TEST_PASSED" != true ]; then
    exit 1
fi
