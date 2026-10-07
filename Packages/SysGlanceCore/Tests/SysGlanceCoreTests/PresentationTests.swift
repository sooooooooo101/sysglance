import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct CardModelBuilderTests {
    let all = MetricKind.allCases

    @Test func ordersCardsByRequestedKinds() {
        let cards = CardModelBuilder.cards(latest: Fixtures.snapshot,
                                           kinds: [.memory, .cpu])
        #expect(cards.map(\.kind) == [.memory, .cpu])
    }

    @Test func omitsBatteryOnDesktopMac() {
        var snapshot = Fixtures.snapshot
        snapshot.battery = nil
        let cards = CardModelBuilder.cards(latest: snapshot, kinds: all)
        #expect(!cards.contains { $0.kind == .battery })
        #expect(cards.count == all.count - 1)
    }

    @Test func memoryCard() {
        let card = CardModelBuilder.card(.memory, latest: Fixtures.snapshot)
        #expect(card.value == "8.4 GB / 16.0 GB")
        #expect(card.detail == "プレッシャー 警告 · スワップ 1.0 GB")
        #expect(card.level == .warning)
        #expect(card.accessibilityLabel == "メモリ 8.4 GB 使用、16.0 GB 中、プレッシャー警告")
    }

    @Test func cpuCard() {
        let card = CardModelBuilder.card(.cpu, latest: Fixtures.snapshot)
        #expect(card.value == "42%")
        #expect(card.gauge == 0.42)
        #expect(card.accessibilityLabel == "CPU 使用率 42%")
    }

    @Test func diskCardCombinesCapacityAndThroughput() {
        let card = CardModelBuilder.card(.disk, latest: Fixtures.snapshot)
        #expect(card.value == "空き 25.6 GB")
        #expect(abs((card.gauge ?? 0) - 0.8956) < 0.001)
        #expect(card.detail == "読み 1.2 MB/s · 書き 0 B/s\n245 GB 中")
        #expect(card.level == .normal)
    }

    @Test func memoryGaugeIsUsedOverTotal() {
        let card = CardModelBuilder.card(.memory, latest: Fixtures.snapshot)
        #expect(abs((card.gauge ?? 0) - 9_000_000_000 / 17_179_869_184) < 0.0001)
    }

    @Test func networkCardHasNoGauge() {
        #expect(CardModelBuilder.card(.network, latest: Fixtures.snapshot).gauge == nil)
    }

    @Test func networkCard() {
        let card = CardModelBuilder.card(.network, latest: Fixtures.snapshot)
        #expect(card.value == "↓ 1.5 MB/s")
        #expect(card.detail == "↑ 34.0 KB/s")
    }

    @Test func batteryCardShowsRemainingTime() {
        let card = CardModelBuilder.card(.battery, latest: Fixtures.snapshot)
        #expect(card.value == "88%")
        #expect(card.detail == "残り 4時間 10分")
    }

    @Test func batteryCardCharging() {
        var snapshot = Fixtures.snapshot
        snapshot.battery = BatteryMetrics(level: 0.5, isCharging: true, isOnAC: true, minutesRemaining: nil)
        let card = CardModelBuilder.card(.battery, latest: snapshot)
        #expect(card.detail == "充電中")
        #expect(card.symbol == "battery.100percent.bolt")
    }

    @Test func systemCardListsTopThreeProcesses() {
        let card = CardModelBuilder.card(.system, latest: Fixtures.snapshot)
        #expect(card.value == "稼働 3日 14時間")
        #expect(card.detail.split(separator: "\n").count == 3)
        #expect(card.detail.hasPrefix("ChatGPT  2.1 GB"))
    }

    @Test func missingDataShowsPlaceholder() {
        let card = CardModelBuilder.card(.cpu, latest: MetricsSnapshot(date: Fixtures.date))
        #expect(card.value == CardModelBuilder.placeholder)
        #expect(card.gauge == nil)
        #expect(card.accessibilityLabel == "CPU 取得できません")
        let none = CardModelBuilder.card(.memory, latest: nil)
        #expect(none.value == CardModelBuilder.placeholder)
    }
}
