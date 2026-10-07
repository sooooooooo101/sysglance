import Foundation
import Observation
import os
import ServiceManagement
import SysGlanceCore

@MainActor
@Observable
final class PanelSettings {
    private enum Keys {
        static let size = "panelSize"
        static let origin = "panelOrigin"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "com.soshi.sysglance", category: "settings")

    var size: LayoutSize {
        didSet { defaults.set(size.rawValue, forKey: Keys.size) }
    }
    private(set) var launchAtLogin: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        size = defaults.string(forKey: Keys.size).flatMap(LayoutSize.init(rawValue:)) ?? .large
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var panelOrigin: CGPoint? {
        get {
            guard let values = defaults.array(forKey: Keys.origin) as? [Double], values.count == 2 else { return nil }
            return CGPoint(x: values[0], y: values[1])
        }
        set {
            if let newValue {
                defaults.set([Double(newValue.x), Double(newValue.y)], forKey: Keys.origin)
            } else {
                defaults.removeObject(forKey: Keys.origin)
            }
        }
    }
}
