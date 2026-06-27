// ──────────────────────────────────────────────
//  Plugin — compiler plugin entry point
//  Registers all macros exposed by this target.
// ──────────────────────────────────────────────

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct KFStatisticsPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TrackableMacro.self,
        EventIDMacro.self,
    ]
}
