import Foundation

/// Default KFStatisticsService implementation wrapping the KFStatistics static engine.
public final class KFStatisticsDefault: KFStatisticsService {

    public init() {}

    public func initialize(config: StatisticsConfig) {
        KFStatistics.configure { $0 = config }
        KFStatistics.start()
    }

    public func unInit() {
        Task { await KFStatistics.shutdown() }
    }

    public func track(_ name: String, _ properties: [String: StatisticsValue], priority: StatisticsPriority) {
        KFStatistics.track(name, properties, priority: priority)
    }
}
