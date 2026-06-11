# Kafka Connect Converter Test

Test the Apicurio Registry Kafka Connect converter package with supported Kafka versions.
Verifies serialization/deserialization works correctly for both Avro and ExtJSON converters.

**Test Plan:** [test-kafka-converter.md](https://github.com/Apicurio/rhboar-releases/blob/main/docs/qe/test-kafka-converter.md)

## Overview

This test validates the `apicurio-registry-distro-connect-converter` package, which provides
Kafka Connect converters for use with Apicurio Registry:

- **AvroConverter** (`io.apicurio.registry.utils.converter.AvroConverter`) - Converts between Kafka Connect's internal format and Avro, storing schemas in Apicurio Registry
- **ExtJsonConverter** (`io.apicurio.registry.utils.converter.ExtJsonConverter`) - Converts between Kafka Connect's internal format and extended JSON with schema references
- **SerdeBasedConverter** (`io.apicurio.registry.utils.converter.SerdeBasedConverter`) - Generic converter using configurable serializer/deserializer

## Test Architecture

```
                          ┌─────────────────┐
                          │  Apicurio       │
                          │  Registry       │
                          │  (port 8080)    │
                          └────────┬────────┘
                                   │ schema registration
                                   │ & lookup
┌──────────┐    ┌─────────────────┐│┌─────────────────┐    ┌──────────┐
│  Source   │───▶│ Kafka Connect   │││ Kafka Connect   │───▶│  Sink    │
│  File     │    │ Source Connector│││ Sink Connector  │    │  File    │
└──────────┘    │ (Avro Converter)│││ (Avro Converter)│    └──────────┘
                └────────┬────────┘│└────────┬────────┘
                         │         │         │
                         ▼         │         ▼
                    ┌──────────────────────────────┐
                    │         Apache Kafka          │
                    │         (port 9092)           │
                    └──────────────────────────────┘
```

## Quick Start

```bash
# Run the full test with defaults
./run-converter-test.sh

# Run interactively (pause between steps)
./run-converter-test.sh --interactive

# Test with specific Kafka version
./run-converter-test.sh --kafka-version 3.8.1

# Test with specific Apicurio version
./run-converter-test.sh --apicurio-version 3.0.7.Final

# Skip the Java test client
./run-converter-test.sh --skip-java-test

# Clean up after testing
./scripts/cleanup.sh --remove-volumes --remove-data
```

## Test Steps

| Step | Description | Script |
|------|-------------|--------|
| A | Deploy Apache Kafka (KRaft mode) | `scripts/step-A-deploy-kafka.sh` |
| B | Deploy Apicurio Registry (in-memory) | `scripts/step-B-deploy-registry.sh` |
| C | Build & deploy Kafka Connect with Apicurio converter | `scripts/step-C-deploy-connect.sh` |
| D | Test Avro converter (source + sink connectors) | `scripts/step-D-test-avro-converter.sh` |
| E | Test ExtJSON converter (source + sink connectors) | `scripts/step-E-test-json-converter.sh` |
| F | Verify schemas registered in Apicurio Registry | `scripts/step-F-verify-schemas.sh` |
| G | Run Java converter test client (direct API test) | `scripts/build-and-run-client.sh` |

## Supported Kafka Versions

The test can be run against different Kafka versions by passing `--kafka-version`:

| Kafka Version | Image Tag | Status |
|---------------|-----------|--------|
| 3.9.1 | `apache/kafka:3.9.1` | Default |
| 3.8.1 | `apache/kafka:3.8.1` | Supported |
| 3.7.2 | `apache/kafka:3.7.2` | Supported |

## Configuration

Edit `.env` to change default versions:

```env
KAFKA_VERSION=3.9.1
APICURIO_VERSION=3.0.7.Final
REGISTRY_IMAGE=quay.io/apicurio/apicurio-registry:3.0.7.Final
```

## Directory Structure

```
converter-testing/
├── README.md                          # This file
├── .env                               # Version configuration
├── run-converter-test.sh              # Main test orchestration
├── docker-compose-kafka.yml           # Kafka broker (KRaft mode)
├── docker-compose-registry.yml        # Apicurio Registry (in-memory)
├── docker-compose-connect.yml         # Kafka Connect with converter
├── connect/
│   ├── Dockerfile                     # Custom Connect image with converter
│   └── start-connect.sh              # Connect worker startup script
├── connectors/
│   ├── avro-file-source.json         # Avro source connector config
│   ├── avro-file-sink.json           # Avro sink connector config
│   ├── json-file-source.json         # ExtJSON source connector config
│   └── json-file-sink.json           # ExtJSON sink connector config
├── clients/
│   └── converter-test/               # Java converter test client
│       ├── pom.xml
│       └── src/main/java/...
├── scripts/
│   ├── common.sh                      # Shared utility functions
│   ├── step-A-deploy-kafka.sh
│   ├── step-B-deploy-registry.sh
│   ├── step-C-deploy-connect.sh
│   ├── step-D-test-avro-converter.sh
│   ├── step-E-test-json-converter.sh
│   ├── step-F-verify-schemas.sh
│   ├── build-and-run-client.sh
│   └── cleanup.sh
├── data/                              # Test data (generated)
└── logs/                              # Test logs (generated)
```

## Java Converter Test Client

The Java test client (`clients/converter-test/`) directly tests the converter API
without needing Kafka Connect. It validates:

1. **AvroConverter** - Simple struct serialization/deserialization roundtrip
2. **AvroConverter** - Default values and optional fields
3. **ExtJsonConverter** - Simple struct roundtrip
4. **SerdeBasedConverter** - Explicit serializer/deserializer configuration
5. **AvroConverter** - Null payload handling

### Building and running independently:

```bash
cd clients/converter-test
mvn clean package -DskipTests
REGISTRY_URL=http://localhost:8080/apis/registry/v3 java -jar target/converter-test-1.0.0-SNAPSHOT.jar
```

## Prerequisites

- Docker and Docker Compose
- Java 17+ and Maven (for the Java test client)
- `curl` and `jq` (for the shell scripts)

## Troubleshooting

### Kafka Connect won't start
Check the converter download in the Dockerfile build:
```bash
docker logs converter-connect
```

### Connector tasks fail
Check the connector status:
```bash
curl -s http://localhost:8083/connectors/avro-file-source/status | jq
```

### No schemas in registry
Verify the registry URL in connector config matches the running registry:
```bash
curl -s http://localhost:8080/apis/registry/v3/search/artifacts | jq
```
