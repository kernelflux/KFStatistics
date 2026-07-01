import KFStatistics
import UMCommon

/// Forwards tracked events to Umeng (友盟) and handles SDK initialization.
///
/// Calls `UMConfigure.initWithAppkey(_:channel:)` on init.
/// `MobClick.event(_:attributes:)` is used for reporting.
///
/// Requires `UMCommon` + `UMDevice` via binaryTarget (umeng-spm mirror repo).
public struct UmengAdapter: StatisticsSink {

    /// - Parameters:
    ///   - appKey: Umeng 后台分配的 AppKey
    ///   - channel: 渠道标记，默认 "App Store"
    public init(appKey: String, channel: String = "App Store") {
        UMConfigure.initWithAppkey(appKey, channel: channel)
    }

    public func report(event: DynamicEvent) {
        var attrs = [String: String]()
        for (k, v) in event.properties {
            if case .string(let s) = v { attrs[k] = s }
        }
        MobClick.event(event.name, attributes: attrs)
    }
}
