
public struct MqttConfig: Sendable {
    public let host: String
    public let port: UInt16
    public let auth: Auth
    public let protocolVersion: MqttProtocolVersion

    public init(host: String, port: UInt16 = 1883, auth: Auth = .anonymous, protocolVersion: MqttProtocolVersion = .v5) {
        self.host = host
        self.port = port
        self.auth = auth
        self.protocolVersion = protocolVersion
    }

    public enum Auth: Sendable, Equatable {
        case anonymous
        case credentials(username: String, password: String)
    }
}
