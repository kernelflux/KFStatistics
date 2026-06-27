// ──────────────────────────────────────────────
//  StatisticsTrackablePage — Custom page naming protocol
//
//  Conform your UIViewController to provide a
//  custom page name for auto-tracking:
//
//      final class ProfileViewController: UIViewController, StatisticsTrackablePage {
//          var trackingPageName: String { "ProfilePage" }
//      }
//
//  Without conformance, the class name is used
//  (e.g. "ProfileViewController").
// ──────────────────────────────────────────────

#if canImport(UIKit)
import UIKit

/// UIViewController 遵守此协议可自定义页面名。
/// 不遵守时默认取 className。
public protocol StatisticsTrackablePage: AnyObject {
    /// 页面埋点名称，默认取类名
    var trackingPageName: String { get }
}

extension StatisticsTrackablePage where Self: UIViewController {
    public var trackingPageName: String {
        let fullName = NSStringFromClass(type(of: self))
        let shortName = fullName.components(separatedBy: ".").last ?? fullName
        // "HomeViewController" → "Home"
        if shortName.hasSuffix("ViewController") {
            return String(shortName.dropLast(14))
        }
        return shortName
    }
}
#endif
