import Foundation

/// Service protocol for the statistics/analytics subsystem.
///
/// Decouples the host from the concrete `KFStatistics` enum, enabling
/// DI registration, mock injection in tests, and the unified startup model.
public protocol KFStatisticsService: AnyObject {
    /// Initialize the statistics engine with the given configuration.
    func initialize(config: StatisticsConfig)

    /// Tear down the service, flushing pending events.
    func unInit()

    /// Track an ad-hoc event by name with typed properties.
    func track(_ name: String, _ properties: [String: StatisticsValue], priority: StatisticsPriority)
}

public extension KFStatisticsService {
    func track(_ name: String, _ properties: [String: StatisticsValue] = [:]) {
        track(name, properties, priority: .default)
    }

    func track(_ name: String, _ values: [String: any Sendable], priority: StatisticsPriority = .default) {
        let properties = values.compactMapValues { value -> StatisticsValue? in
            switch value {
            case let v as String:   return .string(v)
            case let v as Int64:    return .int64(v)
            case let v as Int:      return .int64(Int64(v))
            case let v as UInt64:   return .uint64(v)
            case let v as Double:   return .double(v)
            case let v as Bool:     return .bool(v)
            case let v as Data:     return .data(v)
            default:                return nil
            }
        }
        track(name, properties, priority: priority)
    }
}
