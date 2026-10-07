import SwiftUI
import SysGlanceCore

struct PanelView: View {
    static let contentPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 22

    let store: MetricsStore
    let settings: PanelSettings
    let openDetail: @MainActor () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let size = settings.size
        let cards = CardModelBuilder.cards(latest: store.latest,
                                           history: store.history.suffix(MetricsStore.panelWindow),
                                           kinds: size.kinds)
        MetricsLayout(size: size, cards: cards, sparklineCapacity: MetricsStore.panelWindow, footer: nil)
            .padding(Self.contentPadding)
            .frame(width: size.size.width, height: size.size.height)
            .modifier(PanelBackground(reduceTransparency: reduceTransparency, cornerRadius: Self.cornerRadius))
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
            .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Picker("サイズ", selection: Binding(get: { settings.size }, set: { settings.size = $0 })) {
            ForEach(LayoutSize.allCases) { size in
                Text(size.title).tag(size)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("詳細を開く") { openDetail() }
        Toggle("ログイン時に起動", isOn: Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("SysGlance を終了") { NSApp.terminate(nil) }
    }
}

/// Liquid Glass。「透明度を下げる」設定時は不透明な背景に置き換える。
struct PanelBackground: ViewModifier {
    let reduceTransparency: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
