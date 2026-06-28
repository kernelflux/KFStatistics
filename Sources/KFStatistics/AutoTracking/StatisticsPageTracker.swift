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

/// 页面栈状态，通过 `OSAllocatedUnfairLock` 保证线程安全。
final class PageTrackerState: @unchecked Sendable {

    private struct State {
        var pageStack: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // ── 线程安全的修改方法 ──

    fileprivate func handlePageView(_ notification: Notification) {
        guard let pageName = notification.userInfo?["pageName"] as? String,
              !pageName.isEmpty
        else { return }

        let referrer = state.withLock { s -> String in
            let ref = s.pageStack.last ?? ""
            s.pageStack.append(pageName)
            return ref
        }

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

        state.withLock { s in
            if let index = s.pageStack.lastIndex(of: pageName) {
                s.pageStack.remove(at: index)
            }
        }

        let properties: [String: StatisticsValue] = [
            "pageName": .string(pageName),
            "durationMs": .uint64(durationMs),
        ]

        Task(priority: .utility) {
            KFStatistics.track("PageLeave", properties)
        }
    }
}
