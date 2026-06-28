import KFStatistics
import FirebaseAnalytics

/// Forwards tracked events to Firebase Analytics.
/// Firebase must be configured via `FirebaseApp.configure()` before use.
public struct FirebaseAnalyticsAdapter: StatisticsSink {
    public init() {}

    public func report(event: DynamicEvent) {
        var params: [String: Any] = [:]
        for (key, value) in event.properties {
            switch value {
            case .string(let s): params[key] = s as NSString
            case .int64(let i):  params[key] = i
            case .uint64(let u): params[key] = u
            case .double(let d): params[key] = d
            case .bool(let b):   params[key] = b ? "true" : "false"
            case .data:          break
            }
        }
        Analytics.logEvent(event.name, parameters: params.isEmpty ? nil : params)
    }
}
