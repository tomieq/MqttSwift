# Summary

Pure Swift library for connecting to MQTT broker (MQTT protocol v5.0). It needs to work on MacOS and Linux.

# Project Structure
All new classes/structs/enums put in appropriate folder in separate file. Do not create long files with multiple definitions inside. Although you can add type's extensions in the same file as extended type. If you need extend some object to protocol, name file ObjectType+ProtocolName.swift.

# Available tools
You have docker with images: 
- MQTT broker: `eclipse-mosquitto:2.0.22`
- Swift for Linux: `swift:6.1`
- MQTT local client: `mosquitto_sub`

# Bulding project
- Run `swift build` to build the project on local MacOS
- Run `docker run --rm -t  -v "$PWD":/workspace -w /workspace swift:6.1 swift build` to build the project in linux Swift 6.1 Remember to clean build folder (rm -rf .build) when building for different platform.

# Unit Testing
- Run `swift test --filter UnitTests "$@"` for local unit tests
- Run `docker run --rm -t  -v "$PWD":/workspace -w /workspace swift:6.1 swift test --filter UnitTests "$@" --jobs 1` for unit test on linux

# Integration Testing
- Run `scripts/run_local_integration_tests.sh` to run integration tests local on MacOS. The scripts starts broker in docker and run itegration tests locally.
- Run `scripts/run_docker_integration_tests.sh` to run integration tests in docker for linux. The scripts creates docker network, starts broker and run itegration tests inside docker.

If you even need to start broker manually, just run:  
```
docker run -d \
  --name mosquitto \
  -p 1883:1883 \
  -p 9001:9001 \
  -v $(pwd)/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
  -v $(pwd)/mosquitto/data:/mosquitto/data \
  -v $(pwd)/mosquitto/log:/mosquitto/log \
  eclipse-mosquitto:2.0.22
``` 
Proper config file is already setup at `./mosquitto/config/mosquitto.conf`

# Change commit
Never commit anything, let user review changes.