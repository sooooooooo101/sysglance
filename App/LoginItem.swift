import Observation
import os
import ServiceManagement

/// 「ログイン時に起動」の状態。ウィジェットは本体が書き出す値を表示するので、常駐させたい人向け。
@MainActor
@Observable
final class LoginItem {
    @ObservationIgnored private let logger = Logger(subsystem: "com.soshi.sysglance", category: "login-item")

    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
