import SwiftUI
import SysGlanceCore

extension Level {
    /// 状態色は警告時のみ。通常時はアクセントカラー。
    var tint: Color {
        switch self {
        case .normal: .accentColor
        case .warning: .yellow
        case .critical: .red
        }
    }

    /// 色だけに頼らないためのアイコン。通常時は nil。
    var badgeSymbol: String? {
        switch self {
        case .normal: nil
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
