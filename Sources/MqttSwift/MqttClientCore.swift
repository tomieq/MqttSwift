import Foundation

actor MqttClientCore {
    private let clientID = "MqttSwift-\(UUID().uuidString)"
    private let keepAlive: UInt16 = 30

    private var config: MqttConfig?
    private var transport: MQTTTransport?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var manuallyDisconnected = false
    private var nextPacketID: UInt16 = 1
    private var subscriptions: [String: [@Sendable (MqttMessage) -> Void]] = [:]

    func connect(config: MqttConfig) throws {
        self.config = config
        self.manuallyDisconnected = false
        self.reconnectTask?.cancel()
        self.reconnectTask = nil
        try self.establishConnection(resubscribe: true)
    }

    func send(_ message: MqttMessage) throws {
        try self.ensureConnected()
        try self.transport?.write(MQTTPacketCodec.publishPacket(message, protocolVersion: self.config?.protocolVersion ?? .v5))
    }

    func subscribe(to topic: String, listener: @escaping @Sendable (MqttMessage) -> Void) throws {
        self.subscriptions[topic, default: []].append(listener)
        try self.ensureConnected()
        try self.writeSubscribe(topic: topic)
    }

    func disconnect() {
        self.manuallyDisconnected = true
        self.reconnectTask?.cancel()
        self.receiveTask?.cancel()
        self.keepAliveTask?.cancel()
        self.reconnectTask = nil
        self.receiveTask = nil
        self.keepAliveTask = nil
        if let transport {
            try? transport.write(MQTTPacketCodec.disconnectPacket())
            transport.close()
        }
        transport = nil
    }

    private func ensureConnected() throws {
        guard self.transport == nil else { return }
        try self.establishConnection(resubscribe: true)
    }

    private func establishConnection(resubscribe: Bool) throws {
        guard let config else { throw MQTTError.disconnected }

        let newTransport = MQTTTransport()
        try newTransport.connect(host: config.host, port: config.port)
        try newTransport.write(MQTTPacketCodec.connectPacket(clientID: self.clientID, config: config, keepAlive: self.keepAlive))
        let connack = try newTransport.readPacket()
        try MQTTPacketCodec.validateConnack(typeAndFlags: connack.typeAndFlags, body: connack.body, protocolVersion: config.protocolVersion)

        self.transport?.close()
        self.transport = newTransport
        if resubscribe {
            for topic in self.subscriptions.keys {
                try self.writeSubscribe(topic: topic)
            }
        }
        self.startReceiveLoop(using: newTransport)
        self.startKeepAliveLoop(using: newTransport)
    }

    private func writeSubscribe(topic: String) throws {
        let packetID = self.allocatePacketID()
        try self.transport?.write(MQTTPacketCodec.subscribePacket(packetID: packetID, topic: topic, protocolVersion: self.config?.protocolVersion ?? .v5))
    }

    private func allocatePacketID() -> UInt16 {
        let packetID = self.nextPacketID
        self.nextPacketID = self.nextPacketID == UInt16.max ? 1 : self.nextPacketID + 1
        return packetID
    }

    private func startReceiveLoop(using transport: MQTTTransport) {
        self.receiveTask?.cancel()
        self.receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let packet = try transport.readPacket()
                    await self.handlePacket(typeAndFlags: packet.typeAndFlags, body: packet.body)
                }
            } catch {
                await self.handleConnectionLoss(transport: transport)
            }
        }
    }

    private func startKeepAliveLoop(using transport: MQTTTransport) {
        self.keepAliveTask?.cancel()
        self.keepAliveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.keepAlive) * 500_000_000)
                guard !Task.isCancelled else { return }
                do {
                    try transport.write(MQTTPacketCodec.pingRequestPacket())
                } catch {
                    await self.handleConnectionLoss(transport: transport)
                    return
                }
            }
        }
    }

    private func handlePacket(typeAndFlags: UInt8, body: [UInt8]) {
        switch typeAndFlags >> 4 {
        case 3:
            guard let message = try? MQTTPacketCodec.decodePublish(typeAndFlags: typeAndFlags, body: body, protocolVersion: self.config?.protocolVersion ?? .v5) else { return }
            let listeners = self.subscriptions
                .filter { MQTTTopicMatcher.matches(filter: $0.key, topic: message.topic) }
                .flatMap(\.value)
            for listener in listeners {
                listener(message)
            }
        default:
            break
        }
    }

    private func handleConnectionLoss(transport failedTransport: MQTTTransport) {
        guard self.transport === failedTransport else { return }
        self.transport?.close()
        self.transport = nil
        self.keepAliveTask?.cancel()
        self.keepAliveTask = nil
        guard !self.manuallyDisconnected else { return }
        self.scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard self.reconnectTask == nil else { return }
        self.reconnectTask = Task { [weak self] in
            var delay: UInt64 = 1_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                do {
                    try await self?.reconnect()
                    return
                } catch {
                    delay = min(delay * 2, 30_000_000_000)
                }
            }
        }
    }

    private func reconnect() throws {
        guard !self.manuallyDisconnected else { throw MQTTError.disconnected }
        try self.establishConnection(resubscribe: true)
        self.reconnectTask = nil
    }
}
