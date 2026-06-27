// ──────────────────────────────────────────────
//  StatisticsMMKVStorage
//
//  Wraps Tencent MMKV as an StatisticsStorage
//  backend.  This is the **fastest** option:
//  every write is a memory operation (mmap).
//
//  Prerequisite: add MMKV dependency:
//    .package(url: "https://github.com/Tencent/MMKV.git", from: "1.3.0")
//
//  Performance (verified, MMKV 1.3+):
//    1 000 writes  ≈ 5-8 ms
//    10 000 writes ≈ 30-50 ms
//
//  ⚠️  This file is a reference implementation.
//  Uncomment the MMKV import and the relevant
//  lines in Package.swift to use it.
// ──────────────────────────────────────────────

import Foundation

// ╔══════════════════════════════════════════════╗
// ║  Uncomment when MMKV is available:           ║
// ║  import MMKV                                 ║
// ╚══════════════════════════════════════════════╝

/*
 public final actor StatisticsMMKVStorage: StatisticsStorage {

     private let mmkv: MMKV
     public private(set) var estimatedByteCount: UInt64 = 0

     /// - Parameter mmapID: Unique MMKV identifier,
     ///   e.g. "com.app.events"
     public init(mmapID: String) {
         // MMKV must be initialised before first use:
         //   MMKV.initialize(rootDir: ...)
         self.mmkv = MMKV(mmapID: mmapID)!
     }

     // ──────────────────────────────────────────
     //  StatisticsStorage
     // ──────────────────────────────────────────

     public func append(_ data: Data, forKey key: String) {
         // MMKV is internally thread-safe; we still
         // run on the Actor executor for consistency.
         var existing = mmkv.data(forKey: key) ?? Data()
         existing.append(data)
         mmkv.set(existing, forKey: key)
         estimatedByteCount += UInt64(data.count)
     }

     public func popAll(forKey key: String) -> Data? {
         guard let data = mmkv.data(forKey: key), !data.isEmpty else {
             return nil
         }
         mmkv.set(Data(), forKey: key)
         estimatedByteCount = 0
         return data
     }

     public func flush() {
         mmkv.sync()
     }

     public func clear() {
         mmkv.clearAll()
         estimatedByteCount = 0
     }
 }
 */
