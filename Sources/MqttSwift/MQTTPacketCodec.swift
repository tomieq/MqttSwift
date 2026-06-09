import Foundation

enum MQTTPacketCodec {
    static func connectPacket(clientID: String, config: MqttConfig, keepAlive: UInt16) -> [UInt8] {
        var variableHeader: [UInt8] = []
        self.appendUTF8String("MQTT", to: &variableHeader)
        variableHeader.append(config.protocolVersion.level)

        var flags: UInt8 = 0b0000_0010
        switch config.auth {
        case .anonymous:
            break
        case .credentials:
            flags |= 0b1100_0000
        }
        variableHeader.append(flags)
        self.appendUInt16(keepAlive, to: &variableHeader)
        if config.protocolVersion == .v5 {
            variableHeader.append(0)
        }

        var payload: [UInt8] = []
        self.appendUTF8String(clientID, to: &payload)
        if case let .credentials(username, password) = config.auth {
            self.appendUTF8String(username, to: &payload)
            self.appendUTF8String(password, to: &payload)
        }

        return self.fixedHeader(typeAndFlags: 0x10, remainingLength: variableHeader.count + payload.count) + variableHeader + payload
    }

    static func publishPacket(_ message: MqttMessage, protocolVersion: MqttProtocolVersion = .v5) -> [UInt8] {
        var variableHeader: [UInt8] = []
        self.appendUTF8String(message.topic, to: &variableHeader)
        if protocolVersion == .v5 {
            variableHeader.append(0)
        }

        let payload = Array(message.message.utf8)
        let flags: UInt8 = message.retained ? 0x31 : 0x30
        return self.fixedHeader(typeAndFlags: flags, remainingLength: variableHeader.count + payload.count) + variableHeader + payload
    }

    static func subscribePacket(packetID: UInt16, topic: String, protocolVersion: MqttProtocolVersion = .v5) -> [UInt8] {
        var variableHeader: [UInt8] = []
        self.appendUInt16(packetID, to: &variableHeader)
        if protocolVersion == .v5 {
            variableHeader.append(0)
        }

        var payload: [UInt8] = []
        self.appendUTF8String(topic, to: &payload)
        payload.append(0)

        return self.fixedHeader(typeAndFlags: 0x82, remainingLength: variableHeader.count + payload.count) + variableHeader + payload
    }

    static func pingRequestPacket() -> [UInt8] {
        [0xC0, 0x00]
    }

    static func disconnectPacket() -> [UInt8] {
        [0xE0, 0x00]
    }

    static func validateConnack(typeAndFlags: UInt8, body: [UInt8], protocolVersion: MqttProtocolVersion = .v5) throws {
        switch protocolVersion {
        case .v3_1_1:
            guard typeAndFlags == 0x20, body.count == 2 else { throw MQTTError.invalidPacket }
        case .v5:
            guard typeAndFlags == 0x20, body.count >= 3 else { throw MQTTError.invalidPacket }
        }
        let reasonCode = body[1]
        guard reasonCode == 0 else { throw MQTTError.connectionRefused(reasonCode: reasonCode) }
    }

    static func decodePublish(typeAndFlags: UInt8, body: [UInt8], protocolVersion: MqttProtocolVersion = .v5) throws -> MqttMessage {
        var index = 0
        let topic = try readUTF8String(from: body, index: &index)
        let qos = (typeAndFlags & 0b0000_0110) >> 1
        if qos > 0 {
            guard index + 2 <= body.count else { throw MQTTError.invalidPacket }
            index += 2
        }
        if protocolVersion == .v5 {
            let propertyLength = try readVariableByteInteger(from: body, index: &index)
            guard index + propertyLength <= body.count else { throw MQTTError.invalidPacket }
            index += propertyLength
        }
        guard index <= body.count else { throw MQTTError.invalidPacket }
        let payload = Data(body[index...])
        guard let text = String(data: payload, encoding: .utf8) else { throw MQTTError.malformedString }
        return MqttMessage(topic: topic, message: text, retained: (typeAndFlags & 0x01) == 0x01)
    }

    private static func fixedHeader(typeAndFlags: UInt8, remainingLength: Int) -> [UInt8] {
        [typeAndFlags] + self.encodeVariableByteInteger(remainingLength)
    }

    private static func appendUTF8String(_ value: String, to bytes: inout [UInt8]) {
        let stringBytes = Array(value.utf8)
        self.appendUInt16(UInt16(stringBytes.count), to: &bytes)
        bytes.append(contentsOf: stringBytes)
    }

    private static func appendUInt16(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    private static func readUTF8String(from bytes: [UInt8], index: inout Int) throws -> String {
        guard index + 2 <= bytes.count else { throw MQTTError.invalidPacket }
        let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
        index += 2
        guard index + length <= bytes.count else { throw MQTTError.invalidPacket }
        let stringBytes = bytes[index..<(index + length)]
        index += length
        guard let value = String(bytes: stringBytes, encoding: .utf8) else { throw MQTTError.malformedString }
        return value
    }

    private static func readVariableByteInteger(from bytes: [UInt8], index: inout Int) throws -> Int {
        var multiplier = 1
        var value = 0
        var bytesRead = 0

        while true {
            guard index < bytes.count else { throw MQTTError.invalidPacket }
            let encodedByte = bytes[index]
            index += 1
            value += Int(encodedByte & 127) * multiplier
            bytesRead += 1
            guard bytesRead <= 4 else { throw MQTTError.invalidPacket }
            if (encodedByte & 128) == 0 { return value }
            multiplier *= 128
        }
    }

    private static func encodeVariableByteInteger(_ value: Int) -> [UInt8] {
        var encoded: [UInt8] = []
        var remaining = value
        repeat {
            var byte = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 {
                byte |= 128
            }
            encoded.append(byte)
        } while remaining > 0
        return encoded
    }
}
