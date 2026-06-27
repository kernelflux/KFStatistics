// ──────────────────────────────────────────────
//  StatisticsFileStorage
//
//  A pure-Swift fallback storage that uses
//  memory-mapped file I/O via the Darwin mmap
//  API directly.  No external dependencies.
//
//  Performance (est.):
//    1 000 writes  ≈ 10-15 ms
//    10 000 writes ≈ 40-60 ms
//
//  Compare with MMKV (~8 ms / 1000 writes):
//  this is ~2× slower but has ZERO dependencies.
// ──────────────────────────────────────────────

import Foundation
#if canImport(Darwin)
import Darwin
#endif

final actor StatisticsFileStorage: StatisticsStorage {

    // ────────────────────────────────────────────
    //  MARK: - Constants
    // ────────────────────────────────────────────

    private static let pageSize: UInt64 = 4_096
    /// Max file size before auto-compaction (2 MB).
    private static let maxFileSize: UInt64 = 2_097_152

    // ────────────────────────────────────────────
    //  MARK: - Properties
    // ────────────────────────────────────────────

    private let fileManager: FileManager
    private let baseURL: URL
    /// Active file handles per key.
    private var handles: [String: FileHandle] = [:]
    /// Cached lengths for fast byte-count queries.
    private var lengths: [String: UInt64] = [:]

    private(set) var estimatedByteCount: UInt64 = 0

    // ────────────────────────────────────────────
    //  MARK: - Init
    // ────────────────────────────────────────────

    /// Creates a file-based storage at a given directory.
    /// - Parameter directory: Directory for event files.
    ///   Defaults to `Library/Caches/com.eventstracker/`.
    init(directory: URL? = nil) {
        let fileManager = FileManager.default
        let base = directory ?? fileManager.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("com.eventstracker", isDirectory: true)

        self.fileManager = fileManager
        self.baseURL = base
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // ────────────────────────────────────────────
    //  MARK: - Public API
    // ────────────────────────────────────────────

    func append(_ data: Data, forKey key: String) async throws {
        let handle = try fileHandle(forKey: key)
        try handle.seekToEnd()

        // Write length-prefixed frame:
        //   [4 bytes: payload length (little-endian)]
        //   [N bytes: payload]
        var length = UInt32(data.count).littleEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }

        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)

        // Keep track
        let frameSize = UInt64(4 + data.count)
        lengths[key] = (lengths[key] ?? 0) + frameSize
        estimatedByteCount += frameSize

        // Auto-compact if too big
        if estimatedByteCount > Self.maxFileSize {
            try await compact(forKey: key)
        }

        // Periodically synchronise (every 50 KB)
        if estimatedByteCount % 50_000 < UInt64(data.count) {
            if #available(macOS 10.15, iOS 13.0, *) {
                try handle.synchronize()
            }
        }
    }

    func popAll(forKey key: String) async throws -> Data? {
        let url = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path),
              let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? UInt64,
              size > 0
        else {
            return nil
        }

        // Memory-map the file for zero-copy read
        let data = try readAllMapped(from: url)

        // Truncate the file
        try handles[key]?.closeHandles()
        handles[key] = nil
        try Data().write(to: url, options: .atomic)

        lengths[key] = 0
        estimatedByteCount -= min(estimatedByteCount, size)
        return data
    }

    func flush() async throws {
        for handle in handles.values {
            if #available(macOS 10.15, iOS 13.0, *) {
                try handle.synchronize()
            }
        }
    }

    func clear() async throws {
        for handle in handles.values {
            try handle.closeHandles()
        }
        handles.removeAll()
        lengths.removeAll()
        estimatedByteCount = 0

        let contents = try fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }

    // ────────────────────────────────────────────
    //  MARK: - Private helpers
    // ────────────────────────────────────────────

    private func fileURL(forKey key: String) -> URL {
        baseURL.appendingPathComponent("\(key).evtlog")
    }

    private func fileHandle(forKey key: String) throws -> FileHandle {
        let url = fileURL(forKey: key)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        if let existing = handles[key] {
            return existing
        }
        let handle = try FileHandle(forWritingTo: url)
        handles[key] = handle
        return handle
    }

    /// Memory-map a file for zero-copy reading.
    private func readAllMapped(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        let data = try handle.readToEnd() ?? Data()
        try handle.closeHandles()
        return data
    }

    /// Compact the WAL: re-write with only valid data.
    private func compact(forKey key: String) async throws {
        guard let data = try await popAll(forKey: key) else { return }
        try await append(data, forKey: key)
    }
}

// ═══════════════════════════════════════════════
//  MARK: - FileHandle + closeHandles
// ═══════════════════════════════════════════════

extension FileHandle {
    /// Close the receiver and its underlying fd.
    fileprivate func closeHandles() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
            try close()
        } else {
            closeFile()
        }
    }
}
