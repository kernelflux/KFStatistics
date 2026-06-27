// ──────────────────────────────────────────────
//  StatisticsHTTPTransport — URLSession 默认实现
// ──────────────────────────────────────────────

import Foundation
@_exported import KFStatisticsCore

// ═══════════════════════════════════════════════
//  MARK: - Default HTTP Transport
// ═══════════════════════════════════════════════

/// 基于 URLSession 的默认 HTTP 传输实现。
public struct StatisticsHTTPTransport: StatisticsTransport {

    private let config: StatisticsHTTPTransportConfig
    private let session: URLSession

    public init(config: StatisticsHTTPTransportConfig) {
        self.config = config

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpMaximumConnectionsPerHost = 2
        sessionConfig.httpShouldUsePipelining = true
        sessionConfig.networkServiceType = config.networkServiceType
        sessionConfig.allowsConstrainedNetworkAccess = true
        sessionConfig.allowsExpensiveNetworkAccess = config.allowsCellularAccess
        sessionConfig.timeoutIntervalForResource = 30
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: sessionConfig)
    }

    public func send(batch: StatisticsBatch) async throws -> Int {
        let body: Data
        switch config.encoding {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            body = try encoder.encode(batch)

        case .protobuf:
            throw StatisticsTransportError.encodingError(
                NSError(domain: "KFStatistics", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "protobuf requires swift-protobuf dependency"])
            )

        case .custom(let custom):
            body = try custom.encode(batch)
        }

        let url = config.resolvedURL
        var request = URLRequest(url: url)
        request.httpMethod = config.method
        request.httpBody = body
        request.timeoutInterval = config.timeout

        request.setValue(config.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(config.accept, forHTTPHeaderField: "Accept")
        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw StatisticsTransportError.networkFailure(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StatisticsTransportError.invalidResponse(statusCode: -1)
        }

        switch httpResponse.statusCode {
        case 200...299:
            if let ack = try? JSONDecoder().decode(AckBody.self, from: responseData) {
                return ack.accepted
            }
            return batch.events.count

        case 429:
            throw StatisticsTransportError.invalidResponse(statusCode: 429)

        default:
            throw StatisticsTransportError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }
}

private struct AckBody: Decodable {
    let accepted: Int
}

extension StatisticsHTTPTransport {
    /// 快速初始化：仅需 endpoint，其余全走默认值。
    public init(endpoint: URL) {
        self.init(config: StatisticsHTTPTransportConfig(baseURL: endpoint))
    }
}
