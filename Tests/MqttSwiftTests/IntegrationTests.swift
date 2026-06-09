@testable import MqttSwift
import Foundation
import Testing

@Suite(.serialized)
struct IntegrationTests {
    @Test
    func connectsWithCredentials() async throws {
        let client = MqttClient()
        try await client.connect(config: self.authenticatedConfig())
        await client.disconnect()
    }

    @Test
    func connectsWithMQTT311Credentials() async throws {
        let client = MqttClient()
        try await client.connect(config: self.authenticatedMQTT311Config())
        await client.disconnect()
    }

    @Test
    func connectsAnonymously() async throws {
        let client = MqttClient()
        try await client.connect(config: self.anonymousConfig())
        await client.disconnect()
    }

    @Test
    func subscriberReceivesPublishedMessage() async throws {
        let topic = "test/swift/\(UUID().uuidString)"
        let collector = MessageCollector()
        let subscriber = MqttClient()
        let publisher = MqttClient()

        try await subscriber.connect(config: self.authenticatedConfig())
        try await subscriber.subscribe(to: "\(topic)/#") { message in
            collector.append(message)
        }
        try await publisher.connect(config: self.authenticatedConfig())
        try await publisher.send(MqttMessage(topic: "\(topic)/one", message: "hello"))

        let received = await waitForMessage(from: collector) { $0.topic == "\(topic)/one" }
        #expect(received?.message == "hello")

        await publisher.disconnect()
        await subscriber.disconnect()
    }

    @Test
    func reconnectsAndResubscribesAfterBrokerRestart() async throws {
        guard let containerName = ProcessInfo.processInfo.environment["MQTT_RECONNECT_CONTAINER"] else { return }
        let topic = "test/reconnect/\(UUID().uuidString)"
        let collector = MessageCollector()
        let subscriber = MqttClient()

        try await subscriber.connect(config: self.authenticatedConfig())
        try await subscriber.subscribe(to: "\(topic)/#") { message in
            collector.append(message)
        }

        try restartContainer(named: containerName)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let publisher = MqttClient()
        try await publisher.connect(config: self.authenticatedConfig())
        try await publisher.send(MqttMessage(topic: "\(topic)/after-restart", message: "again"))

        let received = await waitForMessage(from: collector) { $0.topic == "\(topic)/after-restart" }
        #expect(received?.message == "again")

        await publisher.disconnect()
        await subscriber.disconnect()
    }

    private func authenticatedConfig() -> MqttConfig {
        MqttConfig(
            host: self.testHost,
            port: 1883,
            auth: .credentials(username: "tomek", password: "coder")
        )
    }

    private func authenticatedMQTT311Config() -> MqttConfig {
        MqttConfig(
            host: self.testHost,
            port: 1883,
            auth: .credentials(username: "tomek", password: "coder"),
            protocolVersion: .v3_1_1
        )
    }

    private func anonymousConfig() -> MqttConfig {
        MqttConfig(host: self.testHost, port: 1884, auth: .anonymous)
    }

    private var testHost: String {
        ProcessInfo.processInfo.environment["MQTT_TEST_HOST"] ?? "localhost"
    }
}

private func restartContainer(named containerName: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["docker", "restart", containerName]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private final class MessageCollector: @unchecked Sendable {
    let stream: AsyncStream<MqttMessage>
    private let continuation: AsyncStream<MqttMessage>.Continuation

    init() {
        var continuation: AsyncStream<MqttMessage>.Continuation?
        self.stream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        self.continuation = continuation!
    }

    func append(_ message: MqttMessage) {
        self.continuation.yield(message)
    }
}

private func waitForMessage(
    from collector: MessageCollector,
    matching predicate: @escaping @Sendable (MqttMessage) -> Bool
) async -> MqttMessage? {
    await withTaskGroup(of: MqttMessage?.self) { group in
        group.addTask {
            for await message in collector.stream where predicate(message) {
                return message
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
