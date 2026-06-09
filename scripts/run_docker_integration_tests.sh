#!/usr/bin/env bash
set -euo pipefail

NETWORK=${MQTT_DOCKER_NETWORK:-mqtt-test-net}
MQTT_CONTAINER=${MQTT_CONTAINER_NAME:-mosquitto}
SWIFT_CONTAINER=${MQTT_SWIFT_CONTAINER_NAME:-mqtt-swift-test}
MQTT_IMAGE=${MQTT_DOCKER_IMAGE:-eclipse-mosquitto:2.0.22}
SWIFT_IMAGE=${SWIFT_DOCKER_IMAGE:-swift:6.1}
HOST="localhost"

cleanup() {
  docker rm -f "$SWIFT_CONTAINER" "$MQTT_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  swift package clean
}

cleanup
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null

docker run -d \
  --name "$MQTT_CONTAINER" \
  --network "$NETWORK" \
  -p 1883:1883 \
  -p 9001:9001 \
  -v $(pwd)/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
  -v $(pwd)/mosquitto/data:/mosquitto/data \
  -v $(pwd)/mosquitto/log:/mosquitto/log \
  "$MQTT_IMAGE" >/dev/null

echo "Waiting for Mosquitto container ($MQTT_CONTAINER) to accept connections on port 1883..."

attempt=1
while ! nc -z "$HOST" 1883 >/dev/null 2>&1; do
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        echo "Error: Timed out waiting for Mosquitto to start after $MAX_ATTEMPTS seconds."
        exit 1
    fi
    
    echo "Mosquitto is not ready yet... (Attempt $attempt/$MAX_ATTEMPTS)"
    sleep "$TIMEOUT"
    attempt=$((attempt + 1))
done

docker run --rm -t \
  --name "$SWIFT_CONTAINER" \
  --network "$NETWORK" \
  -v "$PWD":/workspace \
  -w /workspace \
  "$SWIFT_IMAGE" \
  swift test --filter IntegrationTests "$@"