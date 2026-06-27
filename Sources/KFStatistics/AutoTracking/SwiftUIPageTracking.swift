// ──────────────────────────────────────────────
//  SwiftUIPageTracking
//
//  SwiftUI 页面自动采集使用 ViewModifier。
//  每个页面显式调用 `.trackPage("Home")`，
//  零侵入 Swizzling，纯 SwiftUI 原生方式。
// ──────────────────────────────────────────────

#if canImport(SwiftUI)
import SwiftUI

// ═══════════════════════════════════════════════
//  MARK: - ViewModifier
// ═══════════════════════════════════════════════

/// 为 SwiftUI View 注入页面埋点。
///
/// ```swift
/// struct HomeView: View {
///     var body: some View {
///         VStack { ... }
///             .trackPage("Home")
///     }
/// }
/// ```
public struct StatisticsPageTrackingModifier: ViewModifier {

    private let pageName: String
    @State private var enterTime: UInt64 = 0

    public init(pageName: String) {
        self.pageName = pageName
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                enterTime = UInt64.now()
                NotificationCenter.default.post(
                    name: .pageView,
                    object: nil,
                    userInfo: [
                        "pageName": pageName,
                        "source": "swiftui",
                        "timestampMs": enterTime,
                    ]
                )
            }
            .onDisappear {
                guard enterTime > 0 else { return }
                let duration = UInt64.now() - enterTime
                NotificationCenter.default.post(
                    name: .pageLeave,
                    object: nil,
                    userInfo: [
                        "pageName": pageName,
                        "source": "swiftui",
                        "durationMs": duration,
                    ]
                )
                enterTime = 0
            }
    }
}

// ═══════════════════════════════════════════════
//  MARK: - View extension
// ═══════════════════════════════════════════════

extension View {
    /// 为页面添加自动埋点。
    ///
    /// - Parameter pageName: 页面名称，展示在分析后台。
    /// - Returns: 添加了埋点的 View。
    public func trackPage(_ pageName: String) -> some View {
        modifier(StatisticsPageTrackingModifier(pageName: pageName))
    }
}
#endif
