# KFStatistics — Swift-Native Analytics SDK

[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/iOS-16.0+-blue?logo=apple)](https://developer.apple.com/ios)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager)

**KFStatistics** is a Swift 6-native event tracking SDK. Built with Actors for lock-free concurrency, `@Trackable` macros for compile-time type-safe events, and a pluggable three-layer pipeline (Serializer → Storage → Transport).

> [中文文档](README_CN.md)

---

## Quick Start

### 1. Add dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/kernelflux/kfstatistics.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "KFStatistics", package: "kfstatistics"),
    ]),
]
```

### 2. Define events

```swift
import KFStatistics

@Trackable
struct Purchase {
    let itemID: String
    let price: Double
    let quantity: Int64
}
```

The `@Trackable` macro auto-generates `EventProtocol` conformance, `Codable`, `Sendable`, and a binary field schema at compile time.

### 3. Configure & start

```swift
KFStatistics.configure { config in
    config.appKey   = "your_app_key"
    config.endpoint = URL(string: "https://api.yourdomain.com/events")!
    config.uploadMode = .intelligent
}
KFStatistics.start()
```

### 4. Track events

```swift
// Compile-time type-safe (via @Trackable)
KFStatistics.track(Purchase(itemID: "sku_123", price: 29.99, quantity: 2))

// Dynamic string-based
KFStatistics.track("Search", ["query": "swift", "results": 5])

// Raw dictionary — auto-boxes into StatisticsValue
KFStatistics.track("Custom", ["key": "value", "count": 42])
```

---

## Architecture

```
         App Layer
            │
   ┌────────▼────────┐
   │   Serializer     │  Struct fields → binary payload
   │   (internal)     │
   └────────┬────────┘
            │ binary Data per event
   ┌────────▼────────┐
   │   Pipeline       │  Batch → PropertyList binary (2–3× faster than JSON)
   │   (Actor)        │
   └────────┬────────┘
            │ binary Data (no base64 expansion)
   ┌────────▼────────┐
   │  Storage (mmap)  │  Crash-safe, append-only WAL
   │   (internal)     │
   └────────┬────────┘
            │ binary Data
   ┌────────▼────────┐
   │  Dispatcher      │  popAll → decode → callback
   │   (Actor)        │
   └────────┬────────┘
            │ StatisticsBatch (native Swift model)
   ┌────────┴────────┐
   │                 │
┌──▼──────┐   ┌──────▼──────────┐
│upload   │   │ Statistics      │
│Handler  │   │ Transport        │
│(simple) │   │ (advanced)       │
│         │   │                  │
│ Free    │   │ Internal         │
│ encoding│   │ encoding choice  │
│ JSON/pb │   │ JSON/binary/etc  │
└─────────┘   └──────────────────┘
```

### Pluggable layers

| Layer | Protocol | Default | Replaceable |
|-------|----------|---------|:-----------:|
| Transport | `StatisticsTransport` (public) | `StatisticsHTTPTransport` (URLSession) | Yes |
| Storage | `StatisticsStorage` (internal) | `StatisticsFileStorage` (mmap WAL) | No |
| Serializer | `StatisticsSerializer` (internal) | `StatisticsBinarySerializer` | No |

---

## Design Rationale

**Actor concurrency over locks.** The pipeline and dispatcher are Swift Actors, eliminating lock contention on the hot path. Event enqueue runs through a lock-free ring buffer, and all I/O (serialization, file write, network) happens off the main thread.

**Binary serialization, not JSON.** Each `@Trackable` struct generates a compile-time field schema (`[FieldDescriptor]`). The serializer uses PropertyList binary format — 2–3× faster than JSON encoding and produces smaller payloads.

**mmap-based storage.** The file storage uses memory-mapped I/O with append-only writes and a write-ahead log, ensuring crash safety: at most 1 event is lost on a crash.

**Macro-driven type safety.** `@Trackable` eliminates stringly-typed event names and dictionary-based parameters. Compile-time code generation guarantees the event schema matches the event data.

---

## Upload Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `.always` | Fire immediately per event | Payments, critical conversions |
| `.batchThreshold` | Fire when count ≥ threshold | Balanced (default 30 events) |
| `.interval` | Fire every N seconds | Low-frequency scenarios |
| `.intelligent` | Threshold + interval + foreground/background | **Recommended** |

```swift
KFStatistics.configure { config in
    config.uploadMode = .intelligent
    config.uploadThreshold = 30
    config.uploadInterval  = 10
}
```

---

## Transport

### Simple: `uploadHandler` (recommended)

```swift
KFStatistics.configure { config in
    config.uploadHandler = { batch in
        let data = try JSONEncoder().encode(batch)
        var req = URLRequest(url: URL(string: "https://api.xxx.com/events")!)
        req.httpMethod = "POST"
        req.httpBody = data
        let (_, resp) = try await URLSession.shared.data(for: req)
        return batch.events.count
    }
}
```

### Advanced: `StatisticsTransport` protocol

```swift
struct GRPCTransport: StatisticsTransport {
    func send(batch: StatisticsBatch) async throws -> Int {
        // Custom gRPC implementation
        return batch.events.count
    }
}

KFStatistics.configure { config in
    config.transport = GRPCTransport()
}
```

When both `uploadHandler` and `transport` are set, `transport` takes priority.

---

## Configuration Reference

| Category | Key | Default | Description |
|----------|-----|---------|-------------|
| Base | `appKey` | `""` | App identifier |
| | `endpoint` | `nil` | Upload URL |
| Upload | `uploadMode` | `.intelligent` | Upload strategy |
| | `uploadThreshold` | `30` | Batch threshold (events) |
| | `uploadInterval` | `10` | Interval (seconds) |
| | `maxRetries` | `3` | Retry count |
| Auto | `enableAutoPageTracking` | `true` | UIKit swizzle-based tracking |
| Network | `enableCompression` | `true` | zlib compression |
| | `httpMethod` | `nil` | Quick setting, e.g. `"PUT"` |
| | `httpHeaders` | `nil` | Custom request headers |
| Privacy | `optOut` | `false` | Disable collection |
| Debug | `logLevel` | `.off` | Log verbosity |

---

## Page Auto-Tracking

### UIKit (zero-code, swizzling)

```swift
// Automatic — "HomeViewController" → page name "Home"
```

Custom name:

```swift
final class ProfileVC: UIViewController, StatisticsTrackablePage {
    var trackingPageName: String { "Profile" }
}
```

### SwiftUI (declarative)

```swift
struct HomeView: View {
    var body: some View {
        VStack { Text("Hello") }
            .trackPage("Home")
    }
}
```

---

## Products

| Product | Description |
|---------|-------------|
| `KFStatistics` | Full SDK (Core + Macros + Runtime) |
| `KFStatisticsCore` | Protocol-only layer — `EventProtocol`, `StatisticsConfig`, `StatisticsTransport` |

---

## Performance

| Operation | Latency |
|-----------|---------|
| Single event enqueue (RingBuffer) | < 1 µs |
| Batch serialize (100 events) | ~1 ms |
| File write (1,000 events) | ~15 ms |
| Main thread blocking | **0** (all Actor) |
| Crash data loss | ≤ 1 event (mmap WAL) |

---

## Requirements

- iOS 16.0+ / macOS 13.0+ / tvOS 16.0+ / watchOS 9.0+ / visionOS 1.0+
- Swift 6.0+ (Xcode 16+)
- SPM

---

## Source Layout

```
Sources/
├── KFStatisticsCore/          ← Protocols + types (zero dependency)
│   ├── EventProtocol.swift        EventProtocol, FieldDescriptor, StatisticsPriority
│   ├── StatisticsConfig.swift     StatisticsConfig, UploadMode, NetworkPolicy
│   ├── StatisticsBatch.swift      Batch model
│   ├── StatisticsTransport.swift  StatisticsTransport protocol, UploadHandler
│   └── StatisticsTrackablePage.swift
├── KFStatistics/              ← Runtime engine (depends on Core + Macros)
│   ├── Statistics.swift           Public entry point (KFStatistics enum)
│   ├── StatisticsPipeline.swift   Actor-based batcher + serializer
│   ├── Serialization/             Binary serializer
│   ├── Storage/                   mmap-based file storage
│   ├── Dispatch/                  Dispatcher actor + transport
│   ├── AutoTracking/              UIKit swizzling + SwiftUI view modifier
│   └── Utility/                   RingBuffer, AnyEvent
├── KFStatisticsMacros/        ← @Trackable macro implementation
└── KFStatisticsTestSupport/   ← Mock storage for testing
```

---

## Industry Comparison

| Feature | KFStatistics | Sentry | Firebase | Amplitude | Mixpanel |
|---------|:-----------:|:------:|:--------:|:---------:|:--------:|
| Pure Swift 6 | ✅ | ❌ | ❌ | ❌ | ❌ |
| Actor concurrency | ✅ | ❌ | ❌ | ❌ | ❌ |
| Macro type safety | ✅ | ❌ | ❌ | ❌ | ❌ |
| Pluggable Transport | ✅ | ✅ | ❌ | ❌ | ❌ |
| 4 upload modes | ✅ | ❌ | ❌ | ❌ | ❌ |
| SwiftUI tracking | ✅ | ✅ | ❌ | ❌ | ❌ |
| mmap crash safety | ✅ | ❌ | ❌ | ❌ | ❌ |

---

## License

[MIT](LICENSE) © KernelFlux
