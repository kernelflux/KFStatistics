// ──────────────────────────────────────────────
//  UIViewController+Tracking
//
//  AOP Method Swizzling — 主流大厂方案。
//  在 `start()` 时 Swizzle 一次，全局生效。
//
//  Hook 方法：
//    viewDidAppear:   → 采集 PageView 事件
//    viewDidDisappear: → 采集 PageLeave 事件（含停留时长）
//
//  性能：
//    Swizzle 后每个 VC 生命周期增加 ≈ 1 msg_send
//    VC 切换是低频操作（< 60 次/s），对性能无影响。
// ──────────────────────────────────────────────

import Foundation

// ═══════════════════════════════════════════════
//  MARK: - Notification names (always visible)
// ═══════════════════════════════════════════════

extension Notification.Name {
    /// Fired when a page appears (viewDidAppear).
    public static let pageView = Notification.Name("com.eventstracker.pageView")
    /// Fired when a page disappears (viewDidDisappear).
    public static let pageLeave = Notification.Name("com.eventstracker.pageLeave")
}

// ═══════════════════════════════════════════════
//  MARK: - UIKit Swizzling
// ═══════════════════════════════════════════════

#if canImport(UIKit)
import UIKit
import ObjectiveC

nonisolated(unsafe) private var pageEnterKey: UInt8 = 0

extension UIViewController {

    /// 页面进入时间戳（ms），用于计算停留时长。
    fileprivate var _pageEnterTime: UInt64 {
        get { (objc_getAssociatedObject(self, &pageEnterKey) as? UInt64) ?? 0 }
        set { objc_setAssociatedObject(self, &pageEnterKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 启动页面自动采集。App 启动时调用一次。
    static func enablePageAutoTracking() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { enablePageAutoTracking() }
            return
        }

        swizzle(
            #selector(UIViewController.viewDidAppear(_:)),
            #selector(UIViewController._et_viewDidAppear(_:))
        )
        swizzle(
            #selector(UIViewController.viewDidDisappear(_:)),
            #selector(UIViewController._et_viewDidDisappear(_:))
        )
    }

    private static func swizzle(_ original: Selector, _ swizzled: Selector) {
        guard let origMethod = class_getInstanceMethod(UIViewController.self, original),
              let swizMethod = class_getInstanceMethod(UIViewController.self, swizzled)
        else { return }

        let didAdd = class_addMethod(
            UIViewController.self, original,
            method_getImplementation(swizMethod),
            method_getTypeEncoding(swizMethod)
        )

        if didAdd {
            class_replaceMethod(
                UIViewController.self, swizzled,
                method_getImplementation(origMethod),
                method_getTypeEncoding(origMethod)
            )
        } else {
            method_exchangeImplementations(origMethod, swizMethod)
        }
    }

    // ── Swizzled: viewDidAppear ──

    @objc private func _et_viewDidAppear(_ animated: Bool) {
        self._et_viewDidAppear(animated)

        // 跳过容器 VC
        guard !isKind(of: UINavigationController.self),
              !isKind(of: UITabBarController.self),
              !isKind(of: UISplitViewController.self)
        else { return }

        // 缓存 className 避免重复 NSStringFromClass 调用
        let cls = NSStringFromClass(type(of: self))
        let pageName = (self as? StatisticsTrackablePage)?.trackingPageName
            ?? cls.components(separatedBy: ".").last ?? "Unknown"

        _pageEnterTime = UInt64.now()

        NotificationCenter.default.post(
            name: .pageView,
            object: nil,
            userInfo: [
                "pageName": pageName,
                "className": cls,
                "timestampMs": _pageEnterTime,
            ]
        )
    }

    // ── Swizzled: viewDidDisappear ──

    @objc private func _et_viewDidDisappear(_ animated: Bool) {
        self._et_viewDidDisappear(animated)

        guard _pageEnterTime > 0 else { return }
        let duration = UInt64.now() - _pageEnterTime

        let cls = NSStringFromClass(type(of: self))
        let pageName = (self as? StatisticsTrackablePage)?.trackingPageName
            ?? cls.components(separatedBy: ".").last ?? "Unknown"

        NotificationCenter.default.post(
            name: .pageLeave,
            object: nil,
            userInfo: [
                "pageName": pageName,
                "className": cls,
                "durationMs": duration,
            ]
        )

        _pageEnterTime = 0
    }
}
#endif
