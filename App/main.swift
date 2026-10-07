import AppKit

// SwiftUI の App ライフサイクルではなく AppKit で起動する。
// 常駐（LSUIElement）＋独自ウィンドウ管理＋URL スキーム受信を素直に扱うため。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
