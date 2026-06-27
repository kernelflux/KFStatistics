// ──────────────────────────────────────────────
//  UMengAdapter — 友盟+ 适配示例
//
//  使用 uploadHandler 即可完成友盟对接，
//  无需实现协议，无需理解内部 pipeline。
// ──────────────────────────────────────────────

import Foundation
import KFStatistics

#if canImport(UMCommon)
import UMCommon

// ═══════════════════════════════════════════════
//  完整友盟对接：~15 行
// ═══════════════════════════════════════════════

// 1️⃣ 初始化友盟
UMConfigure.initWithAppkey("your_app_key", channel: "AppStore")

// 2️⃣ 初始化 KFStatistics，注入上报回调
KFStatistics.configure { config in
    config.uploadHandler = { batch in
        for event in batch.events {
            // 友盟：自定义事件
            if event.eventName != "PageView", event.eventName != "PageLeave" {
                MobClick.event(event.eventName)
            }
        }
        return batch.events.count
    }
}
KFStatistics.start()

// 页面采集由 KFStatistics 自带的 Swizzle 自动完成，
// 不需额外调用 MobClick.beginLogPageView / endLogPageView

// 用户登录/登出同步
func onUserLogin(_ userID: String) {
    MobClick.profileSignInWithPUID(userID)
}
func onUserLogout() {
    MobClick.profileSignOff()
}
#endif
