import KFService
import KFStatisticsCore

final class KFStatisticsStartupTask: BaseStartupTask {
    override var identifier: String { "com.kernelflux.statistics" }

    private let config: StatisticsConfig

    init(config: StatisticsConfig) { self.config = config }

    override func run() async throws {
        let stats = try ServiceContainer.shared.resolve(KFStatisticsService.self)
        stats.initialize(config: config)
    }
}

public struct KFStatisticsStartupModule: StartupModule {
    private let config: StatisticsConfig
    public var tasks: [any StartupTask] { [KFStatisticsStartupTask(config: config)] }
    public init(config: StatisticsConfig) { self.config = config }
}
