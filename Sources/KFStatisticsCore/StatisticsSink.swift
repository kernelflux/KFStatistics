import Foundation

/// Receives tracked events after the core pipeline has written them to disk.
/// Adapters implement this protocol to forward events to third-party analytics SDKs.
public protocol StatisticsSink: Sendable {
    func report(event: DynamicEvent)
}

public struct NoOpStatisticsSink: StatisticsSink {
    public func report(event: DynamicEvent) {}
    public init() {}
}
