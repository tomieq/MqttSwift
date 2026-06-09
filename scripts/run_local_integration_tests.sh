#!/usr/bin/env bash
set -euo pipefail

MQTT_CONTAINER=${MQTT_CONTAINER_NAME:-mosquitto}
MQTT_IMAGE=${MQTT_DOCKER_IMAGE:-eclipse-mosquitto:2.0.22}
HOST="localhost"

cleanup() {
  docker rm -f "$MQTT_CONTAINER" >/dev/null 2>&1 || true
  swift package clean
}

cleanup
trap cleanup EXIT

docker run -d \
  --name "$MQTT_CONTAINER" \
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


swift test --filter IntegrationTests "$@"
docker rm -f "$MQTT_CONTAINER" >/dev/null 2>&1 || true