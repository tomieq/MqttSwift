
public final class MosquittoClient: Sendable {
    public func connect(config: MosquittoConfig) throws {
        // need to support auto reconnecting
    }

    public func send(_ message: MosquittoMessage) throws {
        // send message to the broker
    }

    public func subscribe(to topic: String, listener: @escaping (MosquittoMessage) -> Void) throws {
        // subscribe
    }
}
