# KFStatistics — Swift-Native Analytics SDK

[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/iOS-16.0+-blue?logo=apple)](https://developer.apple.com/ios)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager)

**KFStatistics** is a Swift 6-native event tracking SDK. Built with Actors for lock-free concurrency, `@Trackable` macros for compile-time type-safe events, and a pluggable three-layer pipeline (Serializer → Storage → Transport).

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

### 3. Register via KFService (v3)

```swift
import KFService
import KFStatistics

// In App init
ServiceContainer.shared.install(KFStatisticsAssembly())

// In App.task
try await Engine.run(modules: [
    KFStatisticsStartupModule(config: {
        var c = StatisticsConfig()
        c.appKey = "your_app_key"
        c.uploadMode = .intelligent
        c.uploadThreshold = 50
        return c
    }()),
])
```

### 4. Track events

```swift
// Via DI
let stats = try ServiceContainer.shared.resolve(KFStatisticsService.self)
stats.track("Search", ["query": "swift", "results": 5])

// Or compile-time type-safe (via @Trackable)
KFStatistics.track(Purchase(itemID: "sku_123", price: 29.99, quantity: 2))
```

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
└─────────┘   └──────────────────┘
```

### Pluggable layers

| Layer | Protocol | Default | Replaceable |
|-------|----------|---------|:-----------:|
| Transport | `StatisticsTransport` (public) | `StatisticsHTTPTransport` (URLSession) | Yes |
| Storage | `StatisticsStorage` (internal) | `StatisticsFileStorage` (mmap WAL) | No |
| Serializer | `StatisticsSerializer` (internal) | `StatisticsBinarySerializer` | No |

## KFStatisticsService Protocol (v3)

```swift
public protocol KFStatisticsService: AnyObject {
    func initialize(config: StatisticsConfig)
    func unInit()

    func track(_ name: String, _ properties: [String: StatisticsValue], priority: StatisticsPriority)
}

// Convenience — auto-box Sendable values
extension KFStatisticsService {
    func track(_ name: String, _ values: [String: any Sendable])
}
```

## KFService Integration

| Type | Role |
|------|------|
| `KFStatisticsAssembly` | Implements `ServiceAssembly` — registers `KFStatisticsService` → `KFStatisticsDefault` |
| `KFStatisticsStartupModule` | Implements `StartupModule` — provides `KFStatisticsStartupTask` with config |

```swift
// Install (sync, in App init)
ServiceContainer.shared.install(KFStatisticsAssembly())

// Override with custom impl
ServiceContainer.shared.register(KFStatisticsService.self) { MyStatsService() }

// Run (async, in App.task)
try await Engine.run(modules: [
    KFStatisticsStartupModule(config: myConfig),
])
```

## Upload Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `.always` | Fire immediately per event | Payments, critical conversions |
| `.batchThreshold` | Fire when count ≥ threshold | Balanced (default 30 events) |
| `.interval` | Fire every N seconds | Low-frequency scenarios |
| `.intelligent` | Threshold + interval + foreground/background | **Recommended** |

## Transport

### Simple: `uploadHandler` (recommended)

```swift
var config = StatisticsConfig()
config.uploadHandler = { batch in
    let data = try JSONEncoder().encode(batch)
    var req = URLRequest(url: URL(string: "https://api.xxx.com/events")!)
    req.httpMethod = "POST"
    req.httpBody = data
    let (_, resp) = try await URLSession.shared.data(for: req)
    return batch.events.count
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
var config = StatisticsConfig()
config.transport = GRPCTransport()
```

## Products

| Product | Description |
|---------|-------------|
| `KFStatistics` | Full SDK (Core + Macros + Runtime) |
| `KFStatisticsCore` | Protocol-only layer — `EventProtocol`, `StatisticsConfig`, `StatisticsTransport`, `KFStatisticsService` |

## Performance

| Operation | Latency |
|-----------|---------|
| Single event enqueue (RingBuffer) | < 1 µs |
| Batch serialize (100 events) | ~1 ms |
| File write (1,000 events) | ~15 ms |
| Main thread blocking | **0** (all Actor) |
| Crash data loss | ≤ 1 event (mmap WAL) |

## Requirements

- iOS 16.0+ / macOS 13.0+ / tvOS 16.0+ / watchOS 9.0+ / visionOS 1.0+
- Swift 6.0+ (Xcode 16+)
- SPM

## Source Layout

```
Sources/
├── KFStatisticsCore/          ← Protocols + types (zero dependency)
│   ├── EventProtocol.swift        EventProtocol, FieldDescriptor, StatisticsPriority
│   ├── StatisticsConfig.swift     StatisticsConfig, UploadMode, NetworkPolicy
│   ├── StatisticsBatch.swift      Batch model
│   ├── StatisticsTransport.swift  StatisticsTransport protocol, UploadHandler
│   ├── KFStatisticsService.swift  Service protocol for DI
│   └── StatisticsTrackablePage.swift
├── KFStatistics/              ← Runtime engine + KFStatisticsAssembly + KFStatisticsStartupModule
│   ├── KFStatisticsDefault.swift  Default implementation
│   ├── KFStatisticsAssembly.swift ServiceAssembly
│   ├── KFStatisticsStartupModule.swift
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

## License

[MIT](LICENSE) © KernelFlux
