public enum MqttProtocolVersion: Sendable, Equatable {
    case v3_1_1
    case v5

    var level: UInt8 {
        switch self {
        case .v3_1_1:
            4
        case .v5:
            5
        }
    }
}