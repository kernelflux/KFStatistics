// ──────────────────────────────────────────────
//  StatisticsPageTracker — Auto-tracking coordinator
//
//  监听 NotificationCenter 上的 pageView / pageLeave
//  通知，自动转换为事件并通过 pipeline 采集。
//
//  线程安全：修改通过 actor 转发，不直接依赖
//  NotificationCenter 的调用线程。
// ──────────────────────────────────────────────

import Foundation
import os

/// 页面自动采集协调器。
///
/// 在 `KFStatistics.start()` 时自动启动。
public final class StatisticsPageTracker: @unchecked Sendable {

    // ────────────────────────────────────────────
    //  MARK: - State (actor-isolated via send)
    // ────────────────────────────────────────────

    /// 页面堆栈，用于计算 referrer（来源页）。
    /// 使用 actor 隔离而非锁。
    private let state = PageTrackerState()

    // ────────────────────────────────────────────
    //  MARK: - Init / Deinit
    // ────────────────────────────────────────────

    public init() {
        subscribe()
    }

    deinit {
        unsubscribe()
    }

    // ────────────────────────────────────────────
    //  MARK: - Subscriptions
    // ────────────────────────────────────────────

    /// 使用 block-based API 而非 target-selector，
    /// 避免 weak/strong dance。
    private var observers: [NSObjectProtocol] = []

    private func subscribe() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .pageView, object: nil, queue: .main) {
                [weak state] notification in
                state?.handlePageView(notification)
            },
            center.addObserver(forName: .pageLeave, object: nil, queue: .main) {
                [weak state] notification in
                state?.handlePageLeave(notification)
            },
        ]
    }

    private func unsubscribe() {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }
}

// ═══════════════════════════════════════════════
//  MARK: - Actor-isolated state
// ═══════════════════════════════════════════════

/// 页面栈状态，通过 actor 隔离保证线程安全。
///
/// 注意：此类使用 `@unchecked Sendable` 是因为它在
/// 内部使用 os_unfair_lock 保护可变状态。所有公共
/// 方法线程安全。
final class PageTrackerState: @unchecked Sendable {

    /// 页面堆栈，FIFO。
    private var pageStack: [String] = []
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    init() { lock.initialize(to: os_unfair_lock()) }

    deinit { lock.deinitialize(count: 1); lock.deallocate() }

    // ── 线程安全的修改方法 ──

    fileprivate func handlePageView(_ notification: Notification) {
        guard let pageName = notification.userInfo?["pageName"] as? String,
              !pageName.isEmpty
        else { return }

        os_unfair_lock_lock(lock)
        let referrer = pageStack.last ?? ""
        pageStack.append(pageName)
        os_unfair_lock_unlock(lock)

        let properties: [String: StatisticsValue] = [
            "pageName": .string(pageName),
            "referrer": .string(referrer),
        ]

        Task(priority: .utility) {
            KFStatistics.track("PageView", properties)
        }
    }

    fileprivate func handlePageLeave(_ notification: Notification) {
        guard let pageName = notification.userInfo?["pageName"] as? String,
              let durationMs = notification.userInfo?["durationMs"] as? UInt64
        else { return }

        os_unfair_lock_lock(lock)
        // 只移除最后一个匹配项（栈顶），而非所有匹配项
        if let index = pageStack.lastIndex(of: pageName) {
            pageStack.remove(at: index)
        }
        os_unfair_lock_unlock(lock)

        let properties: [String: StatisticsValue] = [
            "pageName": .string(pageName),
            "durationMs": .uint64(durationMs),
        ]

        Task(priority: .utility) {
            KFStatistics.track("PageLeave", properties)
        }
    }
}
