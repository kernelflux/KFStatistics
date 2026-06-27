// ──────────────────────────────────────────────
//  StatisticsTransport — 可插拔传输层协议
//
//  宿主方实现此协议可完全替换网络层。
//
//  ```swift
//  struct MyGRPCTransport: StatisticsTransport {
//      func send(batch: StatisticsBatch) async throws -> Int { ... }
//  }
//  ```
// ──────────────────────────────────────────────

import Foundation

// ═══════════════════════════════════════════════
//  MARK: - Error
// ═══════════════════════════════════════════════

public enum StatisticsTransportError: Error, Sendable {
    case invalidResponse(statusCode: Int)
    case networkFailure(Error)
    case encodingError(Error)
    case invalidURL(String)
}

// ═══════════════════════════════════════════════
//  MARK: - Transport Protocol
// ═══════════════════════════════════════════════

/// 宿主方实现此协议可完全替换网络层。
public protocol StatisticsTransport: Sendable {
    /// 发送一批事件到服务端。
    /// - Returns: 服务端确认接收的事件数。
    func send(batch: StatisticsBatch) async throws -> Int
}

/// 上报回调类型（推荐使用，比实现协议更简单）。
/// 参数为待发送的事件批次，返回服务端确认接收的事件数。
public typealias StatisticsUploadHandler = @Sendable (StatisticsBatch) async throws -> Int

// ═══════════════════════════════════════════════
//  MARK: - HTTP Transport Configuration
// ═══════════════════════════════════════════════

/// StatisticsHTTPTransport 的详细配置。
public struct StatisticsHTTPTransportConfig: Sendable {
    public var baseURL: URL
    public var method: String
    public var headers: [String: String]
    public var contentType: String
    public var accept: String
    public var queryItems: [URLQueryItem]
    public var encoding: StatisticsEncoding
    public var timeout: TimeInterval
    public var allowsCellularAccess: Bool
    public var networkServiceType: URLRequest.NetworkServiceType

    public var resolvedURL: URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else { return baseURL }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        return components.url ?? baseURL
    }

    public init(
        baseURL: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        contentType: String = "application/json",
        accept: String = "application/json",
        queryItems: [URLQueryItem] = [],
        encoding: StatisticsEncoding = .json,
        timeout: TimeInterval = 15,
        allowsCellularAccess: Bool = true,
        networkServiceType: URLRequest.NetworkServiceType = .background
    ) {
        self.baseURL = baseURL
        self.method = method
        self.headers = headers
        self.contentType = contentType
        self.accept = accept
        self.queryItems = queryItems
        self.encoding = encoding
        self.timeout = timeout
        self.allowsCellularAccess = allowsCellularAccess
        self.networkServiceType = networkServiceType
    }
}

// ═══════════════════════════════════════════════
//  MARK: - Encoding
// ═══════════════════════════════════════════════

public enum StatisticsEncoding: Sendable {
    case json
    case protobuf
    case custom(StatisticsCustomEncoder)

    public var contentType: String {
        switch self {
        case .json:     return "application/json"
        case .protobuf: return "application/x-protobuf"
        case .custom:   return "application/octet-stream"
        }
    }
}

/// 自定义编码器协议。
public protocol StatisticsCustomEncoder: Sendable {
    func encode(_ batch: StatisticsBatch) throws -> Data
}

// ═══════════════════════════════════════════════
//  MARK: - Convenience init
// ═══════════════════════════════════════════════

extension StatisticsHTTPTransportConfig {
    /// 仅用 endpoint 快速初始化。
    public init(endpoint: URL) {
        self.init(baseURL: endpoint)
    }
}
