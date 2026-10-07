# SysGlance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SSD・メモリ・CPU・ネットワーク・バッテリー・稼働時間を、デスクトップに貼り付くリアルタイムパネルと純正 WidgetKit ウィジェットで表示する macOS 26 アプリ「SysGlance」を作る。

**Architecture:** UI 非依存のローカル Swift Package `SysGlanceCore`（モデル・差分計算・フォーマット・OS 読み取り・表示モデル）を、常駐 AppKit アプリ（デスクトップパネル＋詳細ウィンドウ）と WidgetKit 拡張の両方がリンクする。アプリは1秒ごとに計測して App Group の `snapshot.json` を30秒ごとに更新し、ウィジェットはそれを読む。パネルとウィジェットは同じ SwiftUI レイアウト部品（`SharedUI/`）を共有する。

**Tech Stack:** Swift 6（言語モード6）、SwiftUI、AppKit、WidgetKit、Swift Charts、IOKit、Swift Testing、XcodeGen、macOS 26 SDK（Xcode 27）。外部依存なし。

**Spec:** `docs/superpowers/specs/2026-10-07-sysglance-design.md`（§10 に試作検証による変更あり。必ず読むこと）

## Global Constraints

- プロジェクトルート: `~/projects/sysglance`（git リポジトリ、ブランチ `main`）
- Deployment target: macOS 26.0。Swift 言語モード 6。`SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`（警告ゼロ）
- Team ID: `FJW7DK8RB4`、自動署名
- Bundle ID: アプリ `com.soshi.sysglance`、ウィジェット `com.soshi.sysglance.widget`
- App Group: `FJW7DK8RB4.com.soshi.sysglance`、共有ファイル名 `snapshot.json`、`schemaVersion` = 1
- URL スキーム: `sysglance://detail`
- 本体アプリは App Sandbox 無効・Hardened Runtime 有効。ウィジェットは App Sandbox 有効
- 外部ライブラリ禁止（標準フレームワークのみ）。XcodeGen は開発ツールとしてのみ使用し、`*.xcodeproj` はコミットしない
- 計測間隔: 1秒。プロセス一覧 5秒。SSD 空き容量 30秒。履歴 1800点（30分）。パネルのスパークライン 120点（2分）
- ウィジェット再読込: 前回から300秒以上、またはメモリプレッシャー段階の変化時のみ。snapshot 書き出しは30秒ごと
- 鮮度: `capturedAt` から600秒以上で「SysGlanceが起動していません」
- サイズ: Small 170×170（CPU・メモリ）、Medium 364×170（CPU/メモリ/SSD/ネットワーク）、Large 364×382（全項目）
- **`contentTransition(.numericText())` と `Canvas` を UI で使わない**（常駐 CPU が約20%になることを試作で確認済み）
- 常駐 CPU 使用率 < 2%（`top` で5秒×5回の平均）
- UI 文言は日本語。外部へのネットワーク通信は一切しない
- `timeout` コマンドは macOS に無い。使わないこと
- コミットメッセージ末尾に `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. **保存されたパネル位置が画面外**（外部ディスプレイを外した後の起動など）→ パネルはメイン画面の右上に出るべき。Task 9 Step 6 で `defaults write` により再現して確認する。
2. **VPN 接続中のネットワーク速度**（`utun*` と `en0` で二重計上）→ 物理 IF のみを数えるべき。Task 5 の `interfaceFilter` テストで固定する。
3. **本体アプリが終了している／snapshot.json が壊れている状態のウィジェット** → クラッシュせず「SysGlanceが起動していません」を出すべき。Task 4 の `readReturnsNilForMissingOrCorruptFile` と `staleness` テスト、Task 7 Step 7 の手動確認で固定する。
4. **スリープ復帰直後の速度表示**（累積カウンタの巻き戻りや長い空白）→ マイナスや異常値を出さず 0 から再開すべき。Task 2 の `counterDecreaseYieldsZeroAndRebases` / `resetMakesNextSampleABaseline`、Task 5 の `resetBaselinesClearsCPU` で固定する。
5. **UI 変更による CPU 使用率の退行**（数値トランジションやぼかしを足すと20%に跳ねる）→ 常駐 CPU は 2% 未満を保つべき。Task 9 Step 5 の `top` 計測で毎回確認する。

---

## File Structure

```
~/projects/sysglance/
├── .gitignore
├── project.yml                         XcodeGen 定義（アプリ＋ウィジェット＋ローカルパッケージ）
├── README.md                           ビルド・起動手順
├── Packages/SysGlanceCore/             UI 非依存のロジック（swift test 対象）
│   ├── Package.swift
│   ├── Sources/SysGlanceCore/
│   │   ├── Model/Metrics.swift         MetricKind, Level, MemoryPressure, 各メトリクス, MetricsSnapshot
│   │   ├── Model/RingBuffer.swift      固定容量リングバッファ
│   │   ├── Model/Thresholds.swift      警告レベル判定
│   │   ├── Math/Rates.swift            CounterRate, CPUTicks, CPUUsageCalculator
│   │   ├── Math/Motion.swift           CriticalSpring, EdgeSnap
│   │   ├── Format/Fmt.swift            表示用フォーマッタ
│   │   ├── Shared/SnapshotFile.swift   App Group ファイル入出力, WidgetReloadPolicy
│   │   ├── System/CString.swift        C 文字列変換
│   │   ├── System/HostReaders.swift    メモリ・CPU tick・稼働時間
│   │   ├── System/IOReaders.swift      SSD 容量/IO・ネットワーク・バッテリー
│   │   ├── System/ProcessReader.swift  メモリ上位プロセス
│   │   ├── Engine/SamplingEngine.swift 1回分の計測（actor）
│   │   └── Presentation/CardModel.swift 表示モデルと文言
│   └── Tests/SysGlanceCoreTests/       Model/Math/Format/Shared/SystemSmoke/Presentation
├── SharedUI/                           アプリとウィジェット共通の SwiftUI
│   ├── LevelTint.swift
│   ├── Sparkline.swift
│   └── MetricsLayout.swift             LayoutSize と Small/Medium/Large レイアウト
├── App/                                常駐アプリ
│   ├── main.swift, AppDelegate.swift
│   ├── MetricsStore.swift, SnapshotPublisher.swift, PanelSettings.swift
│   ├── Panel/DraggablePanel.swift, Panel/DesktopPanelController.swift, Panel/PanelView.swift
│   ├── Detail/DetailWindowController.swift, Detail/DetailView.swift
│   └── Info.plist, SysGlance.entitlements   （XcodeGen が生成。コミットする）
└── Widget/
    ├── SysGlanceWidget.swift, WidgetViews.swift
    └── Info.plist, SysGlanceWidget.entitlements  （XcodeGen が生成。コミットする）
```

---

### Task 1: Core パッケージとデータモデル

**Files:**
- Modify: `.gitignore`
- Create: `Packages/SysGlanceCore/Package.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Model/Metrics.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Model/RingBuffer.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Model/Thresholds.swift`
- Test: `Packages/SysGlanceCore/Tests/SysGlanceCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `MetricKind`（`cpu, memory, network, disk, battery, system`、`CaseIterable`）、`Level`（`normal, warning, critical`）、`MemoryPressure(sysctlValue: Int32)`、`CPUMetrics(usage:)`、`MemoryMetrics(total:app:wired:compressed:cached:swapUsed:swapTotal:pressure:)` と `.used`、`DiskMetrics(total:available:)` と `.used`、`Throughput(inbound:outbound:)`、`BatteryMetrics(level:isCharging:isOnAC:minutesRemaining:)`、`ProcessUsage(pid:name:memory:)`、`MetricsSnapshot(date:cpu:memory:disk:diskIO:network:battery:uptime:topProcesses:)`（すべて `Codable, Sendable, Equatable`）、`RingBuffer<Element>(capacity:)` の `append`, `elements`, `suffix(_:)`, `last`, `count`, `isEmpty`、`Thresholds.level(for:)`（`MemoryPressure` / `DiskMetrics` / `BatteryMetrics`）

- [ ] **Step 1: .gitignore と Package.swift を作る**

`.gitignore` を以下で置き換える:

```gitignore
.DS_Store
build/
DerivedData/
.build/
.swiftpm/
*.xcodeproj/
xcuserdata/
```

`Packages/SysGlanceCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SysGlanceCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SysGlanceCore", targets: ["SysGlanceCore"]),
    ],
    targets: [
        .target(
            name: "SysGlanceCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "SysGlanceCoreTests",
            dependencies: ["SysGlanceCore"]
        ),
    ]
)
```

- [ ] **Step 2: 失敗するテストを書く**

`Packages/SysGlanceCore/Tests/SysGlanceCoreTests/ModelTests.swift`:

```swift
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct RingBufferTests {
    @Test func keepsInsertionOrderBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.elements == [1, 2])
        #expect(buffer.last == 2)
        #expect(buffer.count == 2)
    }

    @Test func dropsOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { buffer.append(i) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test func suffixReturnsNewestInOldestFirstOrder() {
        var buffer = RingBuffer<Int>(capacity: 4)
        for i in 1...6 { buffer.append(i) }
        #expect(buffer.suffix(2) == [5, 6])
        #expect(buffer.suffix(10) == [3, 4, 5, 6])
    }

    @Test func emptyBuffer() {
        let buffer = RingBuffer<Int>(capacity: 2)
        #expect(buffer.isEmpty)
        #expect(buffer.last == nil)
        #expect(buffer.elements.isEmpty)
    }

    @Test func holdsThirtyMinutesAtOneHertz() {
        var buffer = RingBuffer<Int>(capacity: 1800)
        for i in 0..<2000 { buffer.append(i) }
        #expect(buffer.count == 1800)
        #expect(buffer.elements.first == 200)
    }
}

@Suite struct ThresholdTests {
    @Test func pressureFromSysctl() {
        #expect(MemoryPressure(sysctlValue: 1) == .normal)
        #expect(MemoryPressure(sysctlValue: 2) == .warning)
        #expect(MemoryPressure(sysctlValue: 4) == .critical)
        #expect(MemoryPressure(sysctlValue: 0) == .normal)
        #expect(Thresholds.level(for: MemoryPressure.critical) == .critical)
    }

    @Test func diskLevels() {
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 50)) == .normal)
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 10)) == .normal)
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 9)) == .warning)
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 4)) == .critical)
        #expect(Thresholds.level(for: DiskMetrics(total: 0, available: 0)) == .normal)
    }

    @Test func batteryLevelsIgnoreACPower() {
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.15, isCharging: false, isOnAC: false, minutesRemaining: 30)) == .warning)
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.05, isCharging: false, isOnAC: false, minutesRemaining: 5)) == .critical)
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.05, isCharging: true, isOnAC: true, minutesRemaining: nil)) == .normal)
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.5, isCharging: false, isOnAC: false, minutesRemaining: 120)) == .normal)
    }

    @Test func diskUsedNeverUnderflows() {
        #expect(DiskMetrics(total: 10, available: 20).used == 0)
    }
}
```

- [ ] **Step 3: テストが失敗することを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | tail -5`
Expected: FAIL（`cannot find 'RingBuffer' in scope` などのコンパイルエラー。Sources が空なので「no source files」になる場合もある）

- [ ] **Step 4: 実装する**

`Packages/SysGlanceCore/Sources/SysGlanceCore/Model/Metrics.swift`:

```swift
import Foundation

public enum MetricKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, memory, network, disk, battery, system
    public var id: String { rawValue }
}

public enum Level: Int, Codable, Sendable, Comparable {
    case normal, warning, critical
    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum MemoryPressure: Int, Codable, Sendable {
    case normal = 1, warning = 2, critical = 4

    /// `kern.memorystatus_vm_pressure_level` の値から変換する。未知の値は normal 扱い。
    public init(sysctlValue: Int32) {
        switch sysctlValue {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }
}

public struct CPUMetrics: Codable, Sendable, Equatable {
    /// 0...1
    public var usage: Double
    public init(usage: Double) { self.usage = usage }
}

public struct MemoryMetrics: Codable, Sendable, Equatable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    /// アクティビティモニタの「使用済みメモリ」と同じ定義（App + Wired + 圧縮）。
    public var used: UInt64 { app + wired + compressed }

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
                swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
    }
}

public struct DiskMetrics: Codable, Sendable, Equatable {
    public var total: UInt64
    public var available: UInt64
    public var used: UInt64 { total >= available ? total - available : 0 }
    public init(total: UInt64, available: UInt64) {
        self.total = total
        self.available = available
    }
}

public struct Throughput: Codable, Sendable, Equatable {
    /// bytes/s
    public var inbound: Double
    /// bytes/s
    public var outbound: Double
    public init(inbound: Double, outbound: Double) {
        self.inbound = inbound
        self.outbound = outbound
    }
}

public struct BatteryMetrics: Codable, Sendable, Equatable {
    /// 0...1
    public var level: Double
    public var isCharging: Bool
    public var isOnAC: Bool
    public var minutesRemaining: Int?
    public init(level: Double, isCharging: Bool, isOnAC: Bool, minutesRemaining: Int?) {
        self.level = level
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.minutesRemaining = minutesRemaining
    }
}

public struct ProcessUsage: Codable, Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    /// phys_footprint（アクティビティモニタの「メモリ」列と同じ）
    public var memory: UInt64
    public var id: Int32 { pid }
    public init(pid: Int32, name: String, memory: UInt64) {
        self.pid = pid
        self.name = name
        self.memory = memory
    }
}

public struct MetricsSnapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var cpu: CPUMetrics?
    public var memory: MemoryMetrics?
    public var disk: DiskMetrics?
    /// inbound = 読み込み, outbound = 書き込み
    public var diskIO: Throughput?
    /// inbound = 下り, outbound = 上り
    public var network: Throughput?
    public var battery: BatteryMetrics?
    public var uptime: TimeInterval?
    public var topProcesses: [ProcessUsage]

    public init(date: Date, cpu: CPUMetrics? = nil, memory: MemoryMetrics? = nil, disk: DiskMetrics? = nil,
                diskIO: Throughput? = nil, network: Throughput? = nil, battery: BatteryMetrics? = nil,
                uptime: TimeInterval? = nil, topProcesses: [ProcessUsage] = []) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.diskIO = diskIO
        self.network = network
        self.battery = battery
        self.uptime = uptime
        self.topProcesses = topProcesses
    }
}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/Model/RingBuffer.swift`:

```swift
/// 固定容量のリングバッファ。容量を超えたら最も古い要素から捨てる。
public struct RingBuffer<Element> {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0  // 最も古い要素の位置（満杯時のみ意味を持つ）

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// 古い順
    public var elements: [Element] {
        Array(storage[head...]) + Array(storage[..<head])
    }

    /// 新しい方から最大 n 件（古い順で返す）
    public func suffix(_ n: Int) -> [Element] {
        Array(elements.suffix(n))
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(head + storage.count - 1) % storage.count]
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/Model/Thresholds.swift`:

```swift
public enum Thresholds {
    public static func level(for pressure: MemoryPressure) -> Level {
        switch pressure {
        case .normal: .normal
        case .warning: .warning
        case .critical: .critical
        }
    }

    /// 空き 10% 未満で warning、5% 未満で critical。
    public static func level(for disk: DiskMetrics) -> Level {
        guard disk.total > 0 else { return .normal }
        let ratio = Double(disk.available) / Double(disk.total)
        if ratio < 0.05 { return .critical }
        if ratio < 0.10 { return .warning }
        return .normal
    }

    /// 電源未接続で 20% 未満なら warning、10% 未満なら critical。
    public static func level(for battery: BatteryMetrics) -> Level {
        guard !battery.isOnAC else { return .normal }
        if battery.level < 0.10 { return .critical }
        if battery.level < 0.20 { return .warning }
        return .normal
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"`
Expected: `✔ Test run with 9 tests in 2 suites passed`、warning なし

- [ ] **Step 6: コミット**

```bash
cd ~/projects/sysglance && git add .gitignore Packages && git commit -m "feat(core): add metrics model, ring buffer and thresholds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 差分計算とモーション計算

**Files:**
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Math/Rates.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Math/Motion.swift`
- Test: `Packages/SysGlanceCore/Tests/SysGlanceCoreTests/MathTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `CounterRate()` の `mutating update(value: UInt64, at: TimeInterval) -> Double` と `reset()`；`CPUTicks(user:system:idle:nice:)`（UInt64）；`CPUUsageCalculator()` の `mutating update(_: CPUTicks) -> Double?`（初回・巻き戻りで nil）と `reset()`；`CriticalSpring(position:velocity:target:response:)` の `mutating step(dt:)`, `position`, `velocity`, `target`, `isSettled`；`EdgeSnap.project(velocity:decelerationRate:) -> Double`、`EdgeSnap.target(for: CGRect, in: CGRect, threshold: CGFloat = 24, margin: CGFloat = 16) -> CGPoint`

- [ ] **Step 1: 失敗するテストを書く**

`Packages/SysGlanceCore/Tests/SysGlanceCoreTests/MathTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct CounterRateTests {
    @Test func firstSampleIsZero() {
        var rate = CounterRate()
        #expect(rate.update(value: 1_000, at: 10) == 0)
    }

    @Test func computesBytesPerSecond() {
        var rate = CounterRate()
        _ = rate.update(value: 1_000, at: 10)
        #expect(rate.update(value: 3_000, at: 12) == 1_000)
    }

    @Test func counterDecreaseYieldsZeroAndRebases() {
        var rate = CounterRate()
        _ = rate.update(value: 5_000, at: 1)
        #expect(rate.update(value: 100, at: 2) == 0)
        #expect(rate.update(value: 600, at: 3) == 500)
    }

    @Test func nonPositiveElapsedYieldsZero() {
        var rate = CounterRate()
        _ = rate.update(value: 100, at: 5)
        #expect(rate.update(value: 200, at: 5) == 0)
        #expect(rate.update(value: 300, at: 4) == 0)
    }

    @Test func resetMakesNextSampleABaseline() {
        var rate = CounterRate()
        _ = rate.update(value: 100, at: 1)
        rate.reset()
        #expect(rate.update(value: 10_000, at: 2) == 0)
    }
}

@Suite struct CPUUsageTests {
    @Test func firstSampleIsNil() {
        var calc = CPUUsageCalculator()
        #expect(calc.update(CPUTicks(user: 10, system: 10, idle: 10, nice: 0)) == nil)
    }

    @Test func busyOverTotal() {
        var calc = CPUUsageCalculator()
        _ = calc.update(CPUTicks(user: 100, system: 50, idle: 850, nice: 0))
        let usage = calc.update(CPUTicks(user: 130, system: 60, idle: 900, nice: 10))
        // busy = 30 + 10 + 10 = 50, idle = 50 → 0.5
        #expect(usage == 0.5)
    }

    @Test func noElapsedTicksIsZero() {
        var calc = CPUUsageCalculator()
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        _ = calc.update(ticks)
        #expect(calc.update(ticks) == 0)
    }

    @Test func wrappedCounterIsNil() {
        var calc = CPUUsageCalculator()
        _ = calc.update(CPUTicks(user: 100, system: 100, idle: 100, nice: 0))
        #expect(calc.update(CPUTicks(user: 5, system: 200, idle: 200, nice: 0)) == nil)
    }

    @Test func alwaysWithinUnitRange() {
        var calc = CPUUsageCalculator()
        _ = calc.update(CPUTicks(user: 0, system: 0, idle: 0, nice: 0))
        let usage = calc.update(CPUTicks(user: 1_000, system: 0, idle: 0, nice: 0))
        #expect(usage == 1)
    }
}

@Suite struct SpringTests {
    @Test func convergesToTargetWithoutOvershoot() {
        var spring = CriticalSpring(position: 0, target: 100, response: 0.35)
        var maxPosition = 0.0
        for _ in 0..<120 {
            spring.step(dt: 1.0 / 60)
            maxPosition = max(maxPosition, spring.position)
        }
        #expect(spring.isSettled)
        #expect(abs(spring.position - 100) < 0.5)
        #expect(maxPosition <= 100.0001)
    }

    @Test func inheritsInitialVelocity() {
        var spring = CriticalSpring(position: 0, velocity: 2_000, target: 0, response: 0.35)
        spring.step(dt: 1.0 / 60)
        #expect(spring.position > 0)
    }

    @Test func largeStepDoesNotExplode() {
        var spring = CriticalSpring(position: 0, velocity: 5_000, target: 100, response: 0.35)
        spring.step(dt: 10)
        #expect(abs(spring.position - 100) < 0.5)
        #expect(spring.isSettled)
    }

    @Test func zeroStepIsNoop() {
        var spring = CriticalSpring(position: 3, velocity: 4, target: 10)
        spring.step(dt: 0)
        #expect(spring.position == 3)
        #expect(spring.velocity == 4)
    }
}

@Suite struct EdgeSnapTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func snapsToNearLeftAndTopEdges() {
        let frame = CGRect(x: 10, y: 800 - 300 - 20, width: 320, height: 300)
        let target = EdgeSnap.target(for: frame, in: screen)
        #expect(target == CGPoint(x: 16, y: 800 - 300 - 16))
    }

    @Test func snapsToNearRightEdge() {
        let frame = CGRect(x: 1000 - 320 - 5, y: 300, width: 320, height: 300)
        #expect(EdgeSnap.target(for: frame, in: screen).x == CGFloat(1000 - 320 - 16))
    }

    @Test func keepsPositionAwayFromEdges() {
        let frame = CGRect(x: 300, y: 250, width: 320, height: 300)
        #expect(EdgeSnap.target(for: frame, in: screen) == CGPoint(x: 300, y: 250))
    }

    @Test func clampsOffscreenFrameBackOntoScreen() {
        let frame = CGRect(x: 5_000, y: -2_000, width: 320, height: 300)
        let target = EdgeSnap.target(for: frame, in: screen)
        #expect(target == CGPoint(x: 1000 - 320 - 16, y: 16))
    }

    @Test func screenWithNonZeroOrigin() {
        let second = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -1430, y: 400, width: 320, height: 300)
        #expect(EdgeSnap.target(for: frame, in: second).x == CGFloat(-1440 + 16))
    }

    @Test func projectionMatchesAppleFormula() {
        // 1000pt/s, rate 0.998 → 1 * 0.998 / 0.002 = 499
        #expect(abs(EdgeSnap.project(velocity: 1_000) - 499) < 0.001)
        #expect(EdgeSnap.project(velocity: 0) == 0)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error" | head -3`
Expected: `cannot find 'CounterRate' in scope` などのコンパイルエラー

- [ ] **Step 3: 実装する**

`Packages/SysGlanceCore/Sources/SysGlanceCore/Math/Rates.swift`:

```swift
import Foundation

/// 単調増加する累積カウンタから毎秒の速度を求める。
/// カウンタの減少（スリープ復帰・IF再接続など）や経過時間0以下では 0 を返し、基準を更新する。
public struct CounterRate: Sendable {
    private var lastValue: UInt64?
    private var lastTime: TimeInterval = 0

    public init() {}

    public mutating func update(value: UInt64, at time: TimeInterval) -> Double {
        defer {
            lastValue = value
            lastTime = time
        }
        guard let previous = lastValue else { return 0 }
        let elapsed = time - lastTime
        guard elapsed > 0, value >= previous else { return 0 }
        return Double(value - previous) / elapsed
    }

    public mutating func reset() { lastValue = nil }
}

public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 前回の tick との差分から CPU 使用率（0...1）を求める。
public struct CPUUsageCalculator: Sendable {
    private var last: CPUTicks?

    public init() {}

    /// 初回とカウンタ巻き戻り時は nil。
    public mutating func update(_ ticks: CPUTicks) -> Double? {
        defer { last = ticks }
        guard let last else { return nil }
        guard ticks.user >= last.user, ticks.system >= last.system,
              ticks.idle >= last.idle, ticks.nice >= last.nice else { return nil }
        let busy = Double((ticks.user - last.user) + (ticks.system - last.system) + (ticks.nice - last.nice))
        let idle = Double(ticks.idle - last.idle)
        let total = busy + idle
        guard total > 0 else { return 0 }
        return min(max(busy / total, 0), 1)
    }

    public mutating func reset() { last = nil }
}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/Math/Motion.swift`:

```swift
import CoreGraphics
import Foundation

/// 臨界減衰スプリング（damping 1.0）。Apple の "response" パラメータで指定する。
/// 解析解で進めるので dt が大きくても発散しない。
public struct CriticalSpring: Sendable {
    public var position: Double
    public var velocity: Double
    public var target: Double
    /// 秒。小さいほど速い。
    public let response: Double

    public init(position: Double, velocity: Double = 0, target: Double, response: Double = 0.35) {
        self.position = position
        self.velocity = velocity
        self.target = target
        self.response = response
    }

    public mutating func step(dt: Double) {
        guard dt > 0 else { return }
        let omega = 2 * Double.pi / response
        let x0 = position - target
        let b = velocity + omega * x0
        let decay = exp(-omega * dt)
        position = target + (x0 + b * dt) * decay
        velocity = (velocity - omega * b * dt) * decay
    }

    public var isSettled: Bool {
        abs(position - target) < 0.5 && abs(velocity) < 5
    }
}

public enum EdgeSnap {
    /// Apple の "Designing Fluid Interfaces" と同じ減速投射。速度(pt/s) → 移動距離(pt)。
    public static func project(velocity: Double, decelerationRate: Double = 0.998) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// パネルの着地位置（左下原点）を返す。
    /// 画面端から `threshold` 以内なら端から `margin` の位置へ吸着し、必ず `visible` 内に収める。
    public static func target(for frame: CGRect, in visible: CGRect,
                              threshold: CGFloat = 24, margin: CGFloat = 16) -> CGPoint {
        CGPoint(
            x: axis(min: frame.minX, length: frame.width, lower: visible.minX, upper: visible.maxX,
                    threshold: threshold, margin: margin),
            y: axis(min: frame.minY, length: frame.height, lower: visible.minY, upper: visible.maxY,
                    threshold: threshold, margin: margin)
        )
    }

    private static func axis(min origin: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat,
                             threshold: CGFloat, margin: CGFloat) -> CGFloat {
        let maxOrigin = upper - length
        if origin - lower <= threshold { return Swift.min(lower + margin, Swift.max(lower, maxOrigin)) }
        if upper - (origin + length) <= threshold { return Swift.max(maxOrigin - margin, lower) }
        return Swift.min(Swift.max(origin, lower), Swift.max(lower, maxOrigin))
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"`
Expected: `✔ Test run with 29 tests in 6 suites passed`、warning なし

注意: `CGFloat` と整数リテラルを `#expect` で比較すると型推論で false になる。テストでは `CGFloat(...)` で明示している（変更しないこと）。

- [ ] **Step 5: コミット**

```bash
cd ~/projects/sysglance && git add Packages && git commit -m "feat(core): add counter rate, CPU usage, spring and edge snap math

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 表示用フォーマッタ

**Files:**
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Format/Fmt.swift`
- Test: `Packages/SysGlanceCore/Tests/SysGlanceCoreTests/FormatTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `Fmt.Base`（`.binary` = 1024, `.decimal` = 1000）、`Fmt.bytes(_: UInt64, base:) -> String`、`Fmt.rate(_: Double) -> String`（decimal + "/s"）、`Fmt.percent(_: Double) -> String`、`Fmt.duration(_: TimeInterval) -> String`、`Fmt.ago(from: Date, now: Date) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`Packages/SysGlanceCore/Tests/SysGlanceCoreTests/FormatTests.swift`:

```swift
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct FormatTests {
    @Test(arguments: [
        (UInt64(0), "0 B"),
        (UInt64(999), "999 B"),
        (UInt64(1_000), "1.0 KB"),
        (UInt64(1_500), "1.5 KB"),
        (UInt64(999_600), "1.0 MB"),
        (UInt64(245_107_195_904), "245 GB"),
        (UInt64(25_592_918_572), "25.6 GB"),
    ])
    func decimalBytes(value: UInt64, expected: String) {
        #expect(Fmt.bytes(value, base: .decimal) == expected)
    }

    @Test(arguments: [
        (UInt64(17_179_869_184), "16.0 GB"),
        (UInt64(1_048_576), "1.0 MB"),
        (UInt64(1_023 * 1_024), "1.0 MB"),
        (UInt64(512), "512 B"),
    ])
    func binaryBytes(value: UInt64, expected: String) {
        #expect(Fmt.bytes(value, base: .binary) == expected)
    }

    @Test func rateClampsNegativeAndNonFinite() {
        #expect(Fmt.rate(1_234_567) == "1.2 MB/s")
        #expect(Fmt.rate(-5) == "0 B/s")
        #expect(Fmt.rate(.nan) == "0 B/s")
        #expect(Fmt.rate(.infinity) == "0 B/s")
    }

    @Test func percent() {
        #expect(Fmt.percent(0.424) == "42%")
        #expect(Fmt.percent(0.425) == "43%")
        #expect(Fmt.percent(1.7) == "100%")
        #expect(Fmt.percent(-1) == "0%")
    }

    @Test func duration() {
        #expect(Fmt.duration(59) == "0分")
        #expect(Fmt.duration(12 * 60) == "12分")
        #expect(Fmt.duration(4 * 3600 + 12 * 60) == "4時間 12分")
        #expect(Fmt.duration(3 * 86400 + 4 * 3600 + 59 * 60) == "3日 4時間")
        #expect(Fmt.duration(-10) == "0分")
    }

    @Test func ago() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(Fmt.ago(from: now.addingTimeInterval(-30), now: now) == "たった今")
        #expect(Fmt.ago(from: now.addingTimeInterval(-180), now: now) == "3分前")
        #expect(Fmt.ago(from: now.addingTimeInterval(-7_300), now: now) == "2時間前")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error" | head -3`
Expected: `cannot find 'Fmt' in scope`

- [ ] **Step 3: 実装する**

`Packages/SysGlanceCore/Sources/SysGlanceCore/Format/Fmt.swift`:

```swift
import Foundation

/// 表示用フォーマッタ。ロケールに依存しない決定的な出力にする（テスト容易性のため）。
public enum Fmt {
    public enum Base: Double, Sendable {
        /// メモリ（アクティビティモニタと同じ 1024 基準）
        case binary = 1024
        /// ストレージ・通信速度（Finder と同じ 1000 基準）
        case decimal = 1000
    }

    private static let units = ["B", "KB", "MB", "GB", "TB"]

    public static func bytes(_ value: UInt64, base: Base) -> String {
        var v = Double(value)
        var i = 0
        // 999.5 で繰り上げることで "1000 KB" や "1020 KB" のような表示を避ける
        while v >= 999.5, i < units.count - 1 {
            v /= base.rawValue
            i += 1
        }
        if i == 0 { return "\(value) B" }
        return String(format: v >= 99.95 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        let clamped = bytesPerSecond.isFinite ? min(max(0, bytesPerSecond), 1e18) : 0
        return bytes(UInt64(clamped.rounded()), base: .decimal) + "/s"
    }

    /// 0...1 → "42%"
    public static func percent(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// "3日 4時間" / "4時間 12分" / "12分"
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0)) / 60
        let days = total / (60 * 24)
        let hours = (total / 60) % 24
        let minutes = total % 60
        if days > 0 { return "\(days)日 \(hours)時間" }
        if hours > 0 { return "\(hours)時間 \(minutes)分" }
        return "\(minutes)分"
    }

    /// "たった今" / "3分前" / "2時間前"
    public static func ago(from date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "たった今" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)分前" }
        return "\(minutes / 60)時間前"
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"`
Expected: `✔ Test run with 35 tests in 7 suites passed`、warning なし

- [ ] **Step 5: コミット**

```bash
cd ~/projects/sysglance && git add Packages && git commit -m "feat(core): add deterministic display formatters

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: App Group 共有ファイルとウィジェット再読込ポリシー

**Files:**
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Shared/SnapshotFile.swift`
- Test: `Packages/SysGlanceCore/Tests/SysGlanceCoreTests/SharedTests.swift`（`Fixtures` を定義。Task 6 でも使う）

**Interfaces:**
- Consumes: Task 1 の `MetricsSnapshot`, `MemoryPressure`
- Produces: `SnapshotEnvelope(schemaVersion:capturedAt:snapshot:)`；`SnapshotFile.appGroupID`, `.fileName`, `.schemaVersion`, `.staleAfter`（600）, `.defaultURL() -> URL?`, `.encode(_:capturedAt:) throws -> Data`, `.decode(_:) throws -> SnapshotEnvelope`, `.write(_:capturedAt:to:) throws`, `.read(from:) -> SnapshotEnvelope?`, `.isStale(_:now:) -> Bool`、`SnapshotFile.DecodeError.unsupportedSchema(Int)`；`WidgetReloadPolicy()` の `mutating shouldReload(now: Date, pressure: MemoryPressure?) -> Bool`；テスト用 `Fixtures.date`, `Fixtures.snapshot`

- [ ] **Step 1: 失敗するテストを書く**

`Packages/SysGlanceCore/Tests/SysGlanceCoreTests/SharedTests.swift`:

```swift
import Foundation
import Testing
@testable import SysGlanceCore

enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static let snapshot = MetricsSnapshot(
        date: date,
        cpu: CPUMetrics(usage: 0.42),
        memory: MemoryMetrics(total: 17_179_869_184, app: 4_000_000_000, wired: 3_000_000_000,
                              compressed: 2_000_000_000, cached: 5_000_000_000,
                              swapUsed: 1_073_741_824, swapTotal: 2_147_483_648, pressure: .warning),
        disk: DiskMetrics(total: 245_107_195_904, available: 25_592_918_572),
        diskIO: Throughput(inbound: 1_200_000, outbound: 0),
        network: Throughput(inbound: 1_500_000, outbound: 34_000),
        battery: BatteryMetrics(level: 0.88, isCharging: false, isOnAC: false, minutesRemaining: 250),
        uptime: 3 * 86400 + 14 * 3600,
        topProcesses: [
            ProcessUsage(pid: 10, name: "ChatGPT", memory: 2_285_000_000),
            ProcessUsage(pid: 11, name: "Xcode", memory: 1_858_000_000),
            ProcessUsage(pid: 12, name: "Safari", memory: 1_072_000_000),
            ProcessUsage(pid: 13, name: "Mail", memory: 300_000_000),
        ]
    )
}

@Suite struct SnapshotFileTests {
    @Test func roundTrip() throws {
        let data = try SnapshotFile.encode(Fixtures.snapshot, capturedAt: Fixtures.date)
        let envelope = try SnapshotFile.decode(data)
        #expect(envelope.snapshot == Fixtures.snapshot)
        #expect(envelope.capturedAt == Fixtures.date)
        #expect(envelope.schemaVersion == SnapshotFile.schemaVersion)
    }

    @Test func rejectsUnknownSchema() throws {
        let data = try SnapshotFile.encode(Fixtures.snapshot, capturedAt: Fixtures.date)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 99
        let modified = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: SnapshotFile.DecodeError.unsupportedSchema(99)) {
            try SnapshotFile.decode(modified)
        }
    }

    @Test func readReturnsNilForMissingOrCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("snapshot.json")
        #expect(SnapshotFile.read(from: url) == nil)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(SnapshotFile.read(from: url) == nil)
    }

    @Test func writeThenRead() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshot.json")
        try SnapshotFile.write(Fixtures.snapshot, capturedAt: Fixtures.date, to: url)
        #expect(SnapshotFile.read(from: url)?.snapshot == Fixtures.snapshot)
    }

    @Test func staleness() throws {
        let envelope = try SnapshotFile.decode(SnapshotFile.encode(Fixtures.snapshot, capturedAt: Fixtures.date))
        #expect(!SnapshotFile.isStale(envelope, now: Fixtures.date.addingTimeInterval(599)))
        #expect(SnapshotFile.isStale(envelope, now: Fixtures.date.addingTimeInterval(600)))
    }
}

@Suite struct WidgetReloadPolicyTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func firstCallReloads() {
        var policy = WidgetReloadPolicy()
        let reload = policy.shouldReload(now: t0, pressure: .normal)
        #expect(reload)
    }

    @Test func throttlesWithinFiveMinutes() {
        var policy = WidgetReloadPolicy()
        _ = policy.shouldReload(now: t0, pressure: .normal)
        let early = policy.shouldReload(now: t0.addingTimeInterval(299), pressure: .normal)
        let due = policy.shouldReload(now: t0.addingTimeInterval(300), pressure: .normal)
        #expect(!early)
        #expect(due)
    }

    @Test func pressureChangeReloadsImmediately() {
        var policy = WidgetReloadPolicy()
        _ = policy.shouldReload(now: t0, pressure: .normal)
        let changed = policy.shouldReload(now: t0.addingTimeInterval(10), pressure: .critical)
        let same = policy.shouldReload(now: t0.addingTimeInterval(20), pressure: .critical)
        #expect(changed)
        #expect(!same)
    }

    @Test func missingPressureDoesNotCountAsChange() {
        var policy = WidgetReloadPolicy()
        _ = policy.shouldReload(now: t0, pressure: .warning)
        let missing = policy.shouldReload(now: t0.addingTimeInterval(10), pressure: nil)
        let back = policy.shouldReload(now: t0.addingTimeInterval(20), pressure: .warning)
        #expect(!missing)
        #expect(!back)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error" | head -3`
Expected: `cannot find 'SnapshotFile' in scope`

- [ ] **Step 3: 実装する**

`Packages/SysGlanceCore/Sources/SysGlanceCore/Shared/SnapshotFile.swift`:

```swift
import Foundation

public struct SnapshotEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var capturedAt: Date
    public var snapshot: MetricsSnapshot

    public init(schemaVersion: Int = SnapshotFile.schemaVersion, capturedAt: Date, snapshot: MetricsSnapshot) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.snapshot = snapshot
    }
}

/// 本体アプリ → ウィジェットへ最新値を渡す共有ファイル。
public enum SnapshotFile {
    public static let appGroupID = "FJW7DK8RB4.com.soshi.sysglance"
    public static let fileName = "snapshot.json"
    public static let schemaVersion = 1
    /// これより古いスナップショットは「本体が起動していない」とみなす
    public static let staleAfter: TimeInterval = 600

    public enum DecodeError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    public static func defaultURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    public static func encode(_ snapshot: MetricsSnapshot, capturedAt: Date) throws -> Data {
        let envelope = SnapshotEnvelope(schemaVersion: schemaVersion, capturedAt: capturedAt, snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> SnapshotEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion else {
            throw DecodeError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope
    }

    public static func write(_ snapshot: MetricsSnapshot, capturedAt: Date, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(snapshot, capturedAt: capturedAt).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> SnapshotEnvelope? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    public static func isStale(_ envelope: SnapshotEnvelope, now: Date) -> Bool {
        now.timeIntervalSince(envelope.capturedAt) >= staleAfter
    }
}

/// ウィジェットのタイムライン再読込は OS の予算を消費するため、呼ぶ条件を絞る。
public struct WidgetReloadPolicy: Sendable {
    public static let minimumInterval: TimeInterval = 300
    private var lastReload: Date?
    private var lastPressure: MemoryPressure?

    public init() {}

    /// true を返したら呼び出し側は再読込すること（状態は記録済み）。
    public mutating func shouldReload(now: Date, pressure: MemoryPressure?) -> Bool {
        let pressureChanged = pressure != nil && lastPressure != nil && pressure != lastPressure
        if pressure != nil { lastPressure = pressure }
        let due = lastReload.map { now.timeIntervalSince($0) >= Self.minimumInterval } ?? true
        guard due || pressureChanged else { return false }
        lastReload = now
        return true
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"`
Expected: `✔ Test run with 44 tests in 9 suites passed`、warning なし

注意: `#expect(policy.shouldReload(...))` のように mutating メソッドをマクロ内で呼ぶとコンパイルエラーになる。テストのように一度 `let` に受けること。

- [ ] **Step 5: コミット**

```bash
cd ~/projects/sysglance && git add Packages && git commit -m "feat(core): add snapshot file exchange and widget reload policy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: OS からの読み取りと SamplingEngine

**Files:**
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/System/CString.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/System/HostReaders.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/System/IOReaders.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/System/ProcessReader.swift`
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Engine/SamplingEngine.swift`
- Test: `Packages/SysGlanceCore/Tests/SysGlanceCoreTests/SystemSmokeTests.swift`

**Interfaces:**
- Consumes: Task 1 のモデル、Task 2 の `CounterRate`, `CPUTicks`, `CPUUsageCalculator`
- Produces: `HostReaders.memory() -> MemoryMetrics?`, `.cpuTicks() -> CPUTicks?`, `.uptime(now:) -> TimeInterval?`；`IOReaders.ByteCounters(inbound:outbound:)`, `.diskCapacity(path:) -> DiskMetrics?`, `.internalDiskBytes() -> ByteCounters?`, `.isCountedInterface(name:isLoopback:) -> Bool`, `.networkBytes() -> ByteCounters?`, `.battery() -> BatteryMetrics?`；`ProcessReader.topByMemory(limit:) -> [ProcessUsage]`, `.top(_:limit:)`；`actor SamplingEngine(processInterval: = 5, processLimit: = 10, diskCapacityInterval: = 30, clock:)` の `sample(now: Date = Date()) -> MetricsSnapshot` と `resetBaselines()`

背景（試作で確認済み）:
- `IOBlockStorageDriver` はディスクイメージ分もヒットする。親エントリの `Protocol Characteristics["Physical Interconnect Location"] == "Internal"` だけを数える。
- `NET_RT_IFLIST2` の `if_msghdr2.ifm_data` は 64bit カウンタ。`getifaddrs` の `if_data` は 32bit で 4GB で巻き戻るので使わない。
- `proc_pid_rusage` は他ユーザー（root）のプロセスで失敗する（約1/3）。取れたものだけ使う。
- `String(cString:)` は非推奨（警告＝エラー）。`String(nulTerminated:)` を使う。
- `internal` は Swift の予約語なので変数名に使えない。

- [ ] **Step 1: 失敗するテストを書く**

`Packages/SysGlanceCore/Tests/SysGlanceCoreTests/SystemSmokeTests.swift`:

```swift
import Foundation
import Testing
@testable import SysGlanceCore

/// 実機の OS API を叩くスモークテスト。値の正確さではなく「取れて、妥当な範囲にある」ことを確認する。
@Suite struct SystemSmokeTests {
    @Test func memoryIsPlausible() throws {
        let memory = try #require(HostReaders.memory())
        #expect(memory.total == ProcessInfo.processInfo.physicalMemory)
        #expect(memory.used > 0)
        #expect(memory.used <= memory.total)
    }

    @Test func cpuTicksAdvance() async throws {
        let first = try #require(HostReaders.cpuTicks())
        try await Task.sleep(for: .milliseconds(200))
        let second = try #require(HostReaders.cpuTicks())
        var calc = CPUUsageCalculator()
        _ = calc.update(first)
        let maybeUsage = calc.update(second)
        let usage = try #require(maybeUsage)
        #expect((0...1).contains(usage))
    }

    @Test func uptimeIsPositive() throws {
        let uptime = try #require(HostReaders.uptime())
        #expect(uptime > 0)
    }

    @Test func rootVolumeCapacity() throws {
        let disk = try #require(IOReaders.diskCapacity())
        #expect(disk.total > 0)
        #expect(disk.available <= disk.total)
    }

    @Test func internalDiskCountersExist() throws {
        let bytes = try #require(IOReaders.internalDiskBytes())
        #expect(bytes.inbound > 0)
    }

    @Test func networkCountersExist() {
        #expect(IOReaders.networkBytes() != nil)
    }

    @Test(arguments: [
        ("en0", false, true), ("en7", false, true), ("lo0", true, false), ("utun4", false, false),
        ("awdl0", false, false), ("llw0", false, false), ("bridge0", false, false),
    ])
    func interfaceFilter(name: String, loopback: Bool, counted: Bool) {
        #expect(IOReaders.isCountedInterface(name: name, isLoopback: loopback) == counted)
    }

    @Test func batteryIsNilOrInRange() {
        if let battery = IOReaders.battery() {
            #expect((0...1).contains(battery.level))
        }
    }

    @Test func topProcessesSortedAndLimited() {
        let top = ProcessReader.topByMemory(limit: 5)
        #expect(!top.isEmpty)
        #expect(top.count <= 5)
        #expect(zip(top, top.dropFirst()).allSatisfy { $0.memory >= $1.memory })
    }

    @Test func topSortingIsDeterministic() {
        let list = [ProcessUsage(pid: 3, name: "c", memory: 5), ProcessUsage(pid: 1, name: "a", memory: 5),
                    ProcessUsage(pid: 2, name: "b", memory: 9)]
        #expect(ProcessReader.top(list, limit: 2).map(\.pid) == [2, 1])
        #expect(ProcessReader.top(list, limit: -1).isEmpty)
    }
}

@Suite struct SamplingEngineTests {
    @Test func firstSampleHasBaselinesSecondHasRates() async throws {
        let engine = SamplingEngine()
        let first = await engine.sample()
        #expect(first.cpu == nil)
        #expect(first.memory != nil)
        #expect(first.disk != nil)
        #expect(first.uptime != nil)
        #expect(first.network?.inbound == 0)
        #expect(!first.topProcesses.isEmpty)

        try await Task.sleep(for: .milliseconds(300))
        let second = await engine.sample()
        let cpu = try #require(second.cpu)
        #expect((0...1).contains(cpu.usage))
        #expect((second.network?.inbound ?? -1) >= 0)
    }

    @Test func resetBaselinesClearsCPU() async throws {
        let engine = SamplingEngine()
        _ = await engine.sample()
        try await Task.sleep(for: .milliseconds(100))
        await engine.resetBaselines()
        #expect(await engine.sample().cpu == nil)
    }

    @Test func processListRefreshesOnlyAfterInterval() async {
        let ticker = Ticker()
        let engine = SamplingEngine(processInterval: 5, processLimit: 3, clock: { ticker.now })
        let first = await engine.sample()
        ticker.now = 1
        let second = await engine.sample()
        #expect(first.topProcesses == second.topProcesses)
        #expect(first.topProcesses.count <= 3)
    }
}

final class Ticker: @unchecked Sendable {
    var now: TimeInterval = 0
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error" | head -3`
Expected: `cannot find 'HostReaders' in scope`

- [ ] **Step 3: 実装する**

`Packages/SysGlanceCore/Sources/SysGlanceCore/System/CString.swift`:

```swift
extension String {
    /// NUL 終端の C 文字列バッファから生成する（`String(cString:)` は非推奨のため）。
    init(nulTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/System/HostReaders.swift`:

```swift
import Darwin
import Foundation

/// メモリ・CPU・稼働時間（Mach / sysctl）
public enum HostReaders {
    public static func memory() -> MemoryMetrics? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)

        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (anonymous >= purgeable ? anonymous - purgeable : 0) * page

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let pressure: MemoryPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0
            ? MemoryPressure(sysctlValue: level) : .normal

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0

        return MemoryMetrics(
            total: ProcessInfo.processInfo.physicalMemory,
            app: app,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swapOK ? swap.xsu_used : 0,
            swapTotal: swapOK ? swap.xsu_total : 0,
            pressure: pressure
        )
    }

    public static func cpuTicks() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(load.cpu_ticks.0),    // CPU_STATE_USER
            system: UInt64(load.cpu_ticks.1),  // CPU_STATE_SYSTEM
            idle: UInt64(load.cpu_ticks.2),    // CPU_STATE_IDLE
            nice: UInt64(load.cpu_ticks.3)     // CPU_STATE_NICE
        )
    }

    public static func uptime(now: Date = Date()) -> TimeInterval? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        let bootDate = Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
        return max(0, now.timeIntervalSince(bootDate))
    }
}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/System/IOReaders.swift`:

```swift
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// SSD・ネットワーク・バッテリー（IOKit / sysctl）
public enum IOReaders {
    public struct ByteCounters: Sendable, Equatable {
        public var inbound: UInt64
        public var outbound: UInt64
        public init(inbound: UInt64, outbound: UInt64) {
            self.inbound = inbound
            self.outbound = outbound
        }
    }

    public static func diskCapacity(path: String = "/") -> DiskMetrics? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage,
              total > 0, available >= 0 else { return nil }
        return DiskMetrics(total: UInt64(total), available: UInt64(available))
    }

    /// 内蔵ストレージの累積読み書きバイト数。inbound = 読み込み, outbound = 書き込み。
    /// ディスクイメージ（Physical Interconnect Location が "File" 等）は二重計上になるので除外する。
    public static func internalDiskBytes() -> ByteCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard isInternal(driver: service),
                  let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                      .takeRetainedValue() as? [String: Any] else { continue }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            found = true
        }
        return found ? ByteCounters(inbound: read, outbound: written) : nil
    }

    private static func isInternal(driver: io_object_t) -> Bool {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        let characteristics = IORegistryEntryCreateCFProperty(parent, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        return characteristics?["Physical Interconnect Location"] as? String == "Internal"
    }

    private static let excludedInterfacePrefixes = ["lo", "utun", "awdl", "llw", "bridge", "anpi", "gif", "stf"]

    /// VPN（utun）などの仮想IFは物理IFと二重計上になるので数えない。
    public static func isCountedInterface(name: String, isLoopback: Bool) -> Bool {
        guard !isLoopback else { return false }
        return !excludedInterfacePrefixes.contains { name.hasPrefix($0) }
    }

    /// 全物理IFの累積バイト数（64bitカウンタ）。inbound = 受信, outbound = 送信。
    public static func networkBytes() -> ByteCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(nulTerminated: nameBuffer)
                        let loopback = info.ifm_flags & IFF_LOOPBACK != 0
                        if isCountedInterface(name: name, isLoopback: loopback) {
                            inbound &+= info.ifm_data.ifi_ibytes
                            outbound &+= info.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return ByteCounters(inbound: inbound, outbound: outbound)
    }

    /// 内蔵バッテリーがなければ nil。
    public static func battery() -> BatteryMetrics? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = d[kIOPSTimeToEmptyKey] as? Int
            return BatteryMetrics(
                level: min(max(Double(current) / Double(maximum), 0), 1),
                isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                isOnAC: onAC,
                // -1 は「計算中」
                minutesRemaining: (!onAC && (minutes ?? -1) > 0) ? minutes : nil
            )
        }
        return nil
    }
}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/System/ProcessReader.swift`:

```swift
import Darwin
import Foundation

/// メモリ使用量の多いプロセス。他ユーザー（root 等）のプロセスは権限上読めないので含まれない。
public enum ProcessReader {
    public static func topByMemory(limit: Int) -> [ProcessUsage] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        var usages: [ProcessUsage] = []
        usages.reserveCapacity(Int(filled))
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
            usages.append(ProcessUsage(pid: pid, name: name(of: pid), memory: info.ri_phys_footprint))
        }
        return top(usages, limit: limit)
    }

    /// メモリ降順、同値なら pid 昇順で先頭 limit 件。
    public static func top(_ usages: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        Array(usages.sorted { $0.memory != $1.memory ? $0.memory > $1.memory : $0.pid < $1.pid }.prefix(max(0, limit)))
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(nulTerminated: buffer) : "pid \(pid)"
    }
}
```

`Packages/SysGlanceCore/Sources/SysGlanceCore/Engine/SamplingEngine.swift`:

```swift
import Foundation

/// 各 Reader を呼んで差分計算し、1回分の MetricsSnapshot を作る。
public actor SamplingEngine {
    private var cpu = CPUUsageCalculator()
    private var diskRead = CounterRate()
    private var diskWrite = CounterRate()
    private var netDown = CounterRate()
    private var netUp = CounterRate()
    private var processes: [ProcessUsage] = []
    private var lastProcessSample: TimeInterval?
    private var disk: DiskMetrics?
    private var lastDiskSample: TimeInterval?

    private let processInterval: TimeInterval
    private let processLimit: Int
    /// 空き容量の計算（パージ可能領域の集計）は重いので間隔を空ける
    private let diskCapacityInterval: TimeInterval
    /// 単調増加する時刻（秒）。差分計算はこちらを使い、壁時計の変更に影響されないようにする。
    private let clock: @Sendable () -> TimeInterval

    public init(processInterval: TimeInterval = 5, processLimit: Int = 10, diskCapacityInterval: TimeInterval = 30,
                clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.processInterval = processInterval
        self.processLimit = processLimit
        self.diskCapacityInterval = diskCapacityInterval
        self.clock = clock
    }

    /// スリープ復帰時に呼ぶ。次の sample() は基準取得のみになる。
    public func resetBaselines() {
        cpu.reset()
        diskRead.reset()
        diskWrite.reset()
        netDown.reset()
        netUp.reset()
    }

    public func sample(now: Date = Date()) -> MetricsSnapshot {
        let t = clock()

        let cpuUsage = HostReaders.cpuTicks().flatMap { cpu.update($0) }

        var diskIO: Throughput?
        if let bytes = IOReaders.internalDiskBytes() {
            diskIO = Throughput(inbound: diskRead.update(value: bytes.inbound, at: t),
                                outbound: diskWrite.update(value: bytes.outbound, at: t))
        }

        var network: Throughput?
        if let bytes = IOReaders.networkBytes() {
            network = Throughput(inbound: netDown.update(value: bytes.inbound, at: t),
                                 outbound: netUp.update(value: bytes.outbound, at: t))
        }

        if lastProcessSample.map({ t - $0 >= processInterval }) ?? true {
            processes = ProcessReader.topByMemory(limit: processLimit)
            lastProcessSample = t
        }

        if lastDiskSample.map({ t - $0 >= diskCapacityInterval }) ?? true {
            disk = IOReaders.diskCapacity()
            lastDiskSample = t
        }

        return MetricsSnapshot(
            date: now,
            cpu: cpuUsage.map(CPUMetrics.init(usage:)),
            memory: HostReaders.memory(),
            disk: disk,
            diskIO: diskIO,
            network: network,
            battery: IOReaders.battery(),
            uptime: HostReaders.uptime(now: now),
            topProcesses: processes
        )
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"`
Expected: `✔ Test run with 57 tests in 11 suites passed`、warning なし

- [ ] **Step 5: 値の妥当性を手で確認**

Run:
```bash
cd ~/projects/sysglance/Packages/SysGlanceCore && swift test --filter SamplingEngineTests 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "✘|Test run with"
vm_stat | head -8; sysctl vm.swapusage kern.memorystatus_vm_pressure_level; df -h /
```
Expected: テスト PASS。`vm_stat` / `df` の値が Task 9 で見るパネルの値と同じ桁であること（ここでは記録だけ）。

- [ ] **Step 6: コミット**

```bash
cd ~/projects/sysglance && git add Packages && git commit -m "feat(core): add OS metric readers and sampling engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 表示モデル（CardModel）

**Files:**
- Create: `Packages/SysGlanceCore/Sources/SysGlanceCore/Presentation/CardModel.swift`
- Test: `Packages/SysGlanceCore/Tests/SysGlanceCoreTests/PresentationTests.swift`

**Interfaces:**
- Consumes: Task 1 のモデルと `Thresholds`、Task 3 の `Fmt`、Task 4 の `Fixtures`（テストのみ）
- Produces: `CardModel`（`kind, title, symbol, value, detail, level, gauge: Double?, series: [[Double]], seriesMax: Double?, accessibilityLabel`、`Identifiable` で id = kind）；`CardModelBuilder.placeholder`（"—"）, `.title(of:)`, `.symbol(of:)`, `.pressureLabel(_:)`, `.cards(latest:history:kinds:processLimit: = 3) -> [CardModel]`（バッテリー無しならバッテリーカードを省く）, `.card(_:latest:history:processLimit:) -> CardModel`

- [ ] **Step 1: 失敗するテストを書く**

`Packages/SysGlanceCore/Tests/SysGlanceCoreTests/PresentationTests.swift`:

```swift
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct CardModelBuilderTests {
    let all = MetricKind.allCases

    @Test func ordersCardsByRequestedKinds() {
        let cards = CardModelBuilder.cards(latest: Fixtures.snapshot, history: [Fixtures.snapshot],
                                           kinds: [.memory, .cpu])
        #expect(cards.map(\.kind) == [.memory, .cpu])
    }

    @Test func omitsBatteryOnDesktopMac() {
        var snapshot = Fixtures.snapshot
        snapshot.battery = nil
        let cards = CardModelBuilder.cards(latest: snapshot, history: [], kinds: all)
        #expect(!cards.contains { $0.kind == .battery })
        #expect(cards.count == all.count - 1)
    }

    @Test func memoryCard() {
        let card = CardModelBuilder.card(.memory, latest: Fixtures.snapshot, history: [Fixtures.snapshot])
        #expect(card.value == "8.4 GB / 16.0 GB")
        #expect(card.detail == "プレッシャー 警告 · スワップ 1.0 GB")
        #expect(card.level == .warning)
        #expect(card.accessibilityLabel == "メモリ 8.4 GB 使用、16.0 GB 中、プレッシャー警告")
        #expect(card.seriesMax == 1)
    }

    @Test func cpuCard() {
        let card = CardModelBuilder.card(.cpu, latest: Fixtures.snapshot, history: [Fixtures.snapshot, Fixtures.snapshot])
        #expect(card.value == "42%")
        #expect(card.gauge == 0.42)
        #expect(card.series == [[0.42, 0.42]])
        #expect(card.accessibilityLabel == "CPU 使用率 42%")
    }

    @Test func diskCardCombinesCapacityAndThroughput() {
        let card = CardModelBuilder.card(.disk, latest: Fixtures.snapshot, history: [])
        #expect(card.value == "空き 25.6 GB")
        #expect(abs((card.gauge ?? 0) - 0.8956) < 0.001)
        #expect(card.detail == "読み 1.2 MB/s · 書き 0 B/s\n245 GB 中")
        #expect(card.level == .normal)
        #expect(card.series.count == 2)
    }

    @Test func memoryGaugeIsUsedOverTotal() {
        let card = CardModelBuilder.card(.memory, latest: Fixtures.snapshot, history: [])
        #expect(abs((card.gauge ?? 0) - 9_000_000_000 / 17_179_869_184) < 0.0001)
    }

    @Test func networkCardHasNoGauge() {
        #expect(CardModelBuilder.card(.network, latest: Fixtures.snapshot, history: []).gauge == nil)
    }

    @Test func networkCard() {
        let card = CardModelBuilder.card(.network, latest: Fixtures.snapshot, history: [])
        #expect(card.value == "↓ 1.5 MB/s")
        #expect(card.detail == "↑ 34.0 KB/s")
    }

    @Test func batteryCardShowsRemainingTime() {
        let card = CardModelBuilder.card(.battery, latest: Fixtures.snapshot, history: [])
        #expect(card.value == "88%")
        #expect(card.detail == "残り 4時間 10分")
    }

    @Test func batteryCardCharging() {
        var snapshot = Fixtures.snapshot
        snapshot.battery = BatteryMetrics(level: 0.5, isCharging: true, isOnAC: true, minutesRemaining: nil)
        let card = CardModelBuilder.card(.battery, latest: snapshot, history: [])
        #expect(card.detail == "充電中")
        #expect(card.symbol == "battery.100percent.bolt")
    }

    @Test func systemCardListsTopThreeProcesses() {
        let card = CardModelBuilder.card(.system, latest: Fixtures.snapshot, history: [])
        #expect(card.value == "稼働 3日 14時間")
        #expect(card.detail.split(separator: "\n").count == 3)
        #expect(card.detail.hasPrefix("ChatGPT  2.1 GB"))
    }

    @Test func missingDataShowsPlaceholder() {
        let card = CardModelBuilder.card(.cpu, latest: MetricsSnapshot(date: Fixtures.date), history: [])
        #expect(card.value == CardModelBuilder.placeholder)
        #expect(card.gauge == nil)
        #expect(card.accessibilityLabel == "CPU 取得できません")
        let none = CardModelBuilder.card(.memory, latest: nil, history: [])
        #expect(none.value == CardModelBuilder.placeholder)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error" | head -3`
Expected: `cannot find 'CardModelBuilder' in scope`

- [ ] **Step 3: 実装する**

`Packages/SysGlanceCore/Sources/SysGlanceCore/Presentation/CardModel.swift`:

```swift
import Foundation

/// パネル・ウィジェット・詳細ウィンドウが共通で使う表示モデル。
public struct CardModel: Sendable, Equatable, Identifiable {
    public var kind: MetricKind
    public var title: String
    public var symbol: String
    public var value: String
    /// 複数行可（"\n" 区切り）
    public var detail: String
    public var level: Level
    /// リング表示用の割合（0...1）。割合で表せない項目は nil。
    public var gauge: Double?
    /// 0〜2系列。古い順。
    public var series: [[Double]]
    /// nil なら系列の最大値で自動スケール
    public var seriesMax: Double?
    public var accessibilityLabel: String
    public var id: MetricKind { kind }
}

public enum CardModelBuilder {
    public static let placeholder = "—"

    public static func title(of kind: MetricKind) -> String {
        switch kind {
        case .cpu: "CPU"
        case .memory: "メモリ"
        case .network: "ネットワーク"
        case .disk: "SSD"
        case .battery: "バッテリー"
        case .system: "システム"
        }
    }

    public static func symbol(of kind: MetricKind) -> String {
        switch kind {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .system: "clock"
        }
    }

    public static func pressureLabel(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: "正常"
        case .warning: "警告"
        case .critical: "危険"
        }
    }

    /// `kinds` の順に並べる。バッテリーが取得できない（デスクトップMac）場合はバッテリーカードを省く。
    public static func cards(latest: MetricsSnapshot?, history: [MetricsSnapshot], kinds: [MetricKind],
                             processLimit: Int = 3) -> [CardModel] {
        kinds.compactMap { kind in
            if kind == .battery, latest?.battery == nil { return nil }
            return card(kind, latest: latest, history: history, processLimit: processLimit)
        }
    }

    public static func card(_ kind: MetricKind, latest s: MetricsSnapshot?, history: [MetricsSnapshot],
                            processLimit: Int = 3) -> CardModel {
        var c = CardModel(kind: kind, title: title(of: kind), symbol: symbol(of: kind),
                          value: placeholder, detail: "", level: .normal, gauge: nil, series: [], seriesMax: nil,
                          accessibilityLabel: "\(title(of: kind)) 取得できません")
        switch kind {
        case .cpu:
            c.seriesMax = 1
            c.series = [history.map { $0.cpu?.usage ?? 0 }]
            if let cpu = s?.cpu {
                c.value = Fmt.percent(cpu.usage)
                c.gauge = cpu.usage
                c.accessibilityLabel = "CPU 使用率 \(Fmt.percent(cpu.usage))"
            }
        case .memory:
            c.seriesMax = 1
            c.series = [history.map { m in m.memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0 }]
            if let m = s?.memory {
                let used = Fmt.bytes(m.used, base: .binary)
                let total = Fmt.bytes(m.total, base: .binary)
                let pressure = pressureLabel(m.pressure)
                c.value = "\(used) / \(total)"
                c.gauge = Double(m.used) / Double(max(m.total, 1))
                c.detail = "プレッシャー \(pressure) · スワップ \(Fmt.bytes(m.swapUsed, base: .binary))"
                c.level = Thresholds.level(for: m.pressure)
                c.accessibilityLabel = "メモリ \(used) 使用、\(total) 中、プレッシャー\(pressure)"
            }
        case .network:
            c.series = [history.map { $0.network?.inbound ?? 0 }, history.map { $0.network?.outbound ?? 0 }]
            if let n = s?.network {
                c.value = "↓ \(Fmt.rate(n.inbound))"
                c.detail = "↑ \(Fmt.rate(n.outbound))"
                c.accessibilityLabel = "ネットワーク 下り \(Fmt.rate(n.inbound))、上り \(Fmt.rate(n.outbound))"
            }
        case .disk:
            c.series = [history.map { $0.diskIO?.inbound ?? 0 }, history.map { $0.diskIO?.outbound ?? 0 }]
            if let d = s?.disk {
                let free = Fmt.bytes(d.available, base: .decimal)
                let total = Fmt.bytes(d.total, base: .decimal)
                c.value = "空き \(free)"
                c.gauge = Double(d.used) / Double(max(d.total, 1))
                c.level = Thresholds.level(for: d)
                c.accessibilityLabel = "SSD 空き \(free)、\(total) 中"
                c.detail = "\(total) 中"
            }
            if let io = s?.diskIO {
                let line = "読み \(Fmt.rate(io.inbound)) · 書き \(Fmt.rate(io.outbound))"
                c.detail = c.detail.isEmpty ? line : "\(line)\n\(c.detail)"
                c.accessibilityLabel += "、読み込み \(Fmt.rate(io.inbound))、書き込み \(Fmt.rate(io.outbound))"
            }
        case .battery:
            c.seriesMax = 1
            c.series = [history.map { $0.battery?.level ?? 0 }]
            if let b = s?.battery {
                let state: String
                if b.isCharging {
                    state = "充電中"
                } else if b.isOnAC {
                    state = "電源接続"
                } else if let minutes = b.minutesRemaining {
                    state = "残り \(Fmt.duration(TimeInterval(minutes * 60)))"
                } else {
                    state = "バッテリー駆動"
                }
                c.value = Fmt.percent(b.level)
                c.gauge = b.level
                c.detail = state
                c.level = Thresholds.level(for: b)
                c.symbol = b.isCharging ? "battery.100percent.bolt" : "battery.75percent"
                c.accessibilityLabel = "バッテリー \(Fmt.percent(b.level))、\(state)"
            }
        case .system:
            if let uptime = s?.uptime {
                c.value = "稼働 \(Fmt.duration(uptime))"
                c.accessibilityLabel = "稼働時間 \(Fmt.duration(uptime))"
            }
            let top = Array((s?.topProcesses ?? []).prefix(processLimit))
            if !top.isEmpty {
                c.detail = top.map { "\($0.name)  \(Fmt.bytes($0.memory, base: .binary))" }.joined(separator: "\n")
                c.accessibilityLabel += "、メモリ使用量上位 " + top.map(\.name).joined(separator: "、")
            }
        }
        return c
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"`
Expected: `✔ Test run with 69 tests in 12 suites passed`、warning なし

- [ ] **Step 5: コミット**

```bash
cd ~/projects/sysglance && git add Packages && git commit -m "feat(core): add card presentation model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Xcode プロジェクト、計測ループ、共通レイアウト、純正ウィジェット

アプリはまだウィンドウを持たず、計測して snapshot.json を書くだけ。ウィジェットはそれを表示する。

**Files:**
- Create: `project.yml`
- Create: `SharedUI/LevelTint.swift`, `SharedUI/Sparkline.swift`, `SharedUI/MetricsLayout.swift`
- Create: `App/main.swift`, `App/AppDelegate.swift`（暫定版。Task 9 で置き換える）, `App/MetricsStore.swift`, `App/SnapshotPublisher.swift`
- Create: `Widget/SysGlanceWidget.swift`, `Widget/WidgetViews.swift`
- Generated（コミットする）: `App/Info.plist`, `App/SysGlance.entitlements`, `Widget/Info.plist`, `Widget/SysGlanceWidget.entitlements`

**Interfaces:**
- Consumes: SysGlanceCore 全体
- Produces: `LayoutSize`（`.small/.medium/.large`、`title`, `size: CGSize`, `kinds: [MetricKind]`）、`MetricsLayout(size:cards:sparklineCapacity:footer:)`、`Sparkline(series:maxValue:capacity:tint:)`、`Level.tint: Color`, `Level.badgeSymbol: String?`；`@MainActor @Observable MetricsStore` の `history: RingBuffer<MetricsSnapshot>`, `latest`, `onSample`, `start(resetBaselines:)`, `stop()`, `MetricsStore.historyCapacity`（1800）, `MetricsStore.panelWindow`（120）；`@MainActor SnapshotPublisher(url:)` の `publish(_:now:)`

- [ ] **Step 1: project.yml を作る**

`project.yml`:

```yaml
name: SysGlance
options:
  bundleIdPrefix: com.soshi
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    DEVELOPMENT_TEAM: FJW7DK8RB4
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
    GCC_TREAT_WARNINGS_AS_ERRORS: YES
packages:
  SysGlanceCore:
    path: Packages/SysGlanceCore
targets:
  SysGlance:
    type: application
    platform: macOS
    sources: [App, SharedUI]
    dependencies:
      - package: SysGlanceCore
      - target: SysGlanceWidget
        embed: true
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: SysGlance
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.utilities
        CFBundleURLTypes:
          - CFBundleURLName: com.soshi.sysglance
            CFBundleURLSchemes: [sysglance]
    entitlements:
      path: App/SysGlance.entitlements
      properties:
        com.apple.security.application-groups: [FJW7DK8RB4.com.soshi.sysglance]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.soshi.sysglance
        ENABLE_HARDENED_RUNTIME: YES
  SysGlanceWidget:
    type: app-extension
    platform: macOS
    sources: [Widget, SharedUI]
    dependencies:
      - package: SysGlanceCore
    info:
      path: Widget/Info.plist
      properties:
        CFBundleDisplayName: SysGlance
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Widget/SysGlanceWidget.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups: [FJW7DK8RB4.com.soshi.sysglance]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.soshi.sysglance.widget
        ENABLE_HARDENED_RUNTIME: YES
schemes:
  SysGlance:
    build:
      targets:
        SysGlance: all
        SysGlanceWidget: all
    run:
      config: Debug
```

- [ ] **Step 2: 共通 UI を作る**

`SharedUI/LevelTint.swift`:

```swift
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
```

`SharedUI/Sparkline.swift`:

```swift
import SwiftUI

/// 直近の推移を描く小さな折れ線。最新値が右端に来るよう、データが少ないうちは右寄せで描く。
/// Canvas は CPU ラスタライズになり毎秒の再描画が重いため、GPU で描かれる Shape で実装する。
struct Sparkline: View {
    let series: [[Double]]
    /// nil なら観測最大値で自動スケール（ただし最低 1 KB/s 相当にしてノイズを拡大しない）
    let maxValue: Double?
    let capacity: Int
    let tint: Color

    private static let autoScaleFloor = 1_000.0

    var body: some View {
        let observed = series.flatMap { $0 }.max() ?? 0
        let peak = maxValue ?? max(observed, Self.autoScaleFloor)
        ZStack {
            ForEach(Array(series.enumerated()), id: \.offset) { index, values in
                SparklineShape(values: values, peak: peak, capacity: capacity)
                    .stroke(index == 0 ? tint : tint.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SparklineShape: Shape {
    let values: [Double]
    let peak: Double
    let capacity: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard peak > 0, capacity > 1, values.count > 1 else { return path }
        let step = rect.width / CGFloat(capacity - 1)
        let visible = values.suffix(capacity)
        let offset = CGFloat(capacity - visible.count)
        for (i, value) in visible.enumerated() {
            let ratio = CGFloat(min(max(value / peak, 0), 1))
            let point = CGPoint(x: rect.minX + (offset + CGFloat(i)) * step,
                                y: rect.maxY - 1 - ratio * (rect.height - 2))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
```

`SharedUI/MetricsLayout.swift`:

```swift
import SwiftUI
import SysGlanceCore

/// パネルとウィジェットで共通のサイズ。macOS のデスクトップウィジェットとほぼ同じ寸法。
enum LayoutSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    /// 外形（ウィジェットのコンテンツ余白 16pt を含む）
    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }

    var kinds: [MetricKind] {
        switch self {
        case .small: [.cpu, .memory]
        case .medium: [.cpu, .memory, .disk, .network]
        case .large: MetricKind.allCases
        }
    }
}

/// サイズごとのレイアウト。余白・背景は呼び出し側（パネル / containerBackground）が持つ。
struct MetricsLayout: View {
    let size: LayoutSize
    let cards: [CardModel]
    /// スパークラインの横幅に対応する点数。0 ならスパークラインを描かない（ウィジェット）。
    let sparklineCapacity: Int
    /// "3分前" など。リアルタイム表示では nil。
    let footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch size {
            case .small:
                SmallLayout(cards: cards)
            case .medium:
                MediumLayout(cards: cards, sparklineCapacity: sparklineCapacity)
            case .large:
                LargeLayout(cards: cards, sparklineCapacity: sparklineCapacity)
            }
            if let footer {
                Spacer(minLength: 4)
                Text(footer).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SmallLayout: View {
    let cards: [CardModel]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cards) { card in
                RingStat(card: card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RingStat: View {
    let card: CardModel

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(max(card.gauge ?? 0, 0), 1))
                    .stroke(card.level.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(card.gauge.map(Fmt.percent) ?? CardModelBuilder.placeholder)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            HStack(spacing: 2) {
                Text(card.title)
                if let badge = card.level.badgeSymbol {
                    Image(systemName: badge).foregroundStyle(card.level.tint)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
    }
}

private struct MediumLayout: View {
    let cards: [CardModel]
    let sparklineCapacity: Int

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { i in
                GridRow {
                    CompactCell(card: cards[i], sparklineCapacity: sparklineCapacity)
                    if i + 1 < cards.count {
                        CompactCell(card: cards[i + 1], sparklineCapacity: sparklineCapacity)
                    }
                }
            }
        }
    }
}

/// Medium 用：タイトル・値・（あれば）小さなスパークライン
private struct CompactCell: View {
    let card: CardModel
    let sparklineCapacity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardHeader(card: card)
            CardValue(card: card, font: .system(.callout, design: .rounded).weight(.semibold))
            if sparklineCapacity > 0, !card.series.isEmpty {
                Sparkline(series: card.series, maxValue: card.seriesMax, capacity: sparklineCapacity, tint: card.level.tint)
                    .frame(height: 16)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
    }
}

private struct LargeLayout: View {
    let cards: [CardModel]
    let sparklineCapacity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        CardHeader(card: card)
                        CardValue(card: card, font: .system(.callout, design: .rounded).weight(.semibold))
                        if card.kind == .system || card.kind == .disk, !card.detail.isEmpty {
                            Text(card.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(card.kind == .system ? 3 : 1)
                        }
                    }
                    Spacer(minLength: 6)
                    if sparklineCapacity > 0, !card.series.isEmpty {
                        Sparkline(series: card.series, maxValue: card.seriesMax, capacity: sparklineCapacity, tint: card.level.tint)
                            .frame(width: 88, height: 24)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(card.accessibilityLabel)
            }
        }
    }
}

private struct CardHeader: View {
    let card: CardModel

    var body: some View {
        Label(card.title, systemImage: card.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct CardValue: View {
    let card: CardModel
    let font: Font

    var body: some View {
        HStack(spacing: 4) {
            // numericText トランジションはぼかしを伴い、ガラス上で毎秒 CPU 描画を誘発するため使わない
            Text(card.kind == .network ? "\(card.value)  \(card.detail)" : card.value)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let badge = card.level.badgeSymbol {
                Image(systemName: badge).font(.caption).foregroundStyle(card.level.tint)
            }
        }
    }
}
```

- [ ] **Step 3: アプリの計測ループと書き出しを作る**

`App/main.swift`:

```swift
import AppKit

// SwiftUI の App ライフサイクルではなく AppKit で起動する。
// 常駐（LSUIElement）＋独自ウィンドウ管理＋URL スキーム受信を素直に扱うため。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

`App/AppDelegate.swift`（暫定版。パネルと詳細ウィンドウは Task 8・9 で追加する）:

```swift
import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let publisher = SnapshotPublisher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        store.start()
    }
}
```

`App/MetricsStore.swift`:

```swift
import Foundation
import Observation
import SysGlanceCore

@MainActor
@Observable
final class MetricsStore {
    /// 1秒間隔で30分
    static let historyCapacity = 1800
    /// パネルのスパークラインは直近2分
    static let panelWindow = 120

    private(set) var history = RingBuffer<MetricsSnapshot>(capacity: historyCapacity)
    var latest: MetricsSnapshot? { history.last }

    @ObservationIgnored var onSample: ((MetricsSnapshot) -> Void)?
    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private var loop: Task<Void, Never>?

    func start(resetBaselines: Bool = false) {
        guard loop == nil else { return }
        loop = Task { [weak self, engine] in
            if resetBaselines { await engine.resetBaselines() }
            while !Task.isCancelled {
                let snapshot = await engine.sample()
                guard let self, !Task.isCancelled else { return }
                self.history.append(snapshot)
                self.onSample?(snapshot)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
```

`App/SnapshotPublisher.swift`:

```swift
import Foundation
import os
import SysGlanceCore
import WidgetKit

/// ウィジェット用に最新値を App Group へ書き出す。
@MainActor
final class SnapshotPublisher {
    static let writeInterval: TimeInterval = 30

    private let url: URL?
    private var lastWrite: Date?
    private var policy = WidgetReloadPolicy()
    private let logger = Logger(subsystem: "com.soshi.sysglance", category: "snapshot")

    init(url: URL? = SnapshotFile.defaultURL()) {
        self.url = url
        if url == nil {
            logger.error("App Group container is unavailable; widget will not update")
        }
    }

    func publish(_ snapshot: MetricsSnapshot, now: Date = Date()) {
        guard let url else { return }
        let writeDue = lastWrite.map { now.timeIntervalSince($0) >= Self.writeInterval } ?? true
        let reload = policy.shouldReload(now: now, pressure: snapshot.memory?.pressure)
        guard writeDue || reload else { return }
        do {
            try SnapshotFile.write(snapshot, capturedAt: now, to: url)
            lastWrite = now
        } catch {
            logger.error("Failed to write snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
```

- [ ] **Step 4: ウィジェットを作る**

`Widget/SysGlanceWidget.swift`:

```swift
import SwiftUI
import SysGlanceCore
import WidgetKit

@main
struct SysGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SysGlanceWidget", provider: SnapshotProvider()) { entry in
            SysGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("SysGlance")
        .description("CPU・メモリ・SSD などの稼働状況")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, envelope: SnapshotEnvelope(capturedAt: .now, snapshot: .preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(SnapshotEntry(date: .now, envelope: load()))
        }
    }

    /// 同じスナップショットで5分おきのエントリを作り、「○分前」と鮮度判定を進める。
    /// 新しい値は本体アプリの reloadAllTimelines() で届く。
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let envelope = load()
        let entries = (0..<4).map { SnapshotEntry(date: now.addingTimeInterval(Double($0) * 300), envelope: envelope) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func load() -> SnapshotEnvelope? {
        SnapshotFile.defaultURL().flatMap(SnapshotFile.read(from:))
    }
}

extension MetricsSnapshot {
    /// ウィジェットギャラリー用のサンプル値
    static let preview = MetricsSnapshot(
        date: .now,
        cpu: CPUMetrics(usage: 0.23),
        memory: MemoryMetrics(total: 17_179_869_184, app: 5_000_000_000, wired: 2_500_000_000,
                              compressed: 1_500_000_000, cached: 4_000_000_000,
                              swapUsed: 0, swapTotal: 0, pressure: .normal),
        disk: DiskMetrics(total: 500_000_000_000, available: 180_000_000_000),
        diskIO: Throughput(inbound: 2_400_000, outbound: 800_000),
        network: Throughput(inbound: 1_200_000, outbound: 90_000),
        battery: BatteryMetrics(level: 0.8, isCharging: false, isOnAC: false, minutesRemaining: 300),
        uptime: 2 * 86400 + 5 * 3600,
        topProcesses: [
            ProcessUsage(pid: 1, name: "Safari", memory: 1_500_000_000),
            ProcessUsage(pid: 2, name: "Xcode", memory: 1_200_000_000),
            ProcessUsage(pid: 3, name: "Music", memory: 400_000_000),
        ]
    )
}
```

`Widget/WidgetViews.swift`:

```swift
import SwiftUI
import SysGlanceCore
import WidgetKit

struct SysGlanceWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var size: LayoutSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }

    var body: some View {
        Group {
            if let envelope = entry.envelope, !SnapshotFile.isStale(envelope, now: entry.date) {
                MetricsLayout(size: size,
                              cards: CardModelBuilder.cards(latest: envelope.snapshot, history: [], kinds: size.kinds),
                              sparklineCapacity: 0,
                              footer: Fmt.ago(from: envelope.capturedAt, now: entry.date))
            } else {
                StaleView()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "sysglance://detail"))
    }
}

private struct StaleView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pause.circle").font(.title2).foregroundStyle(.secondary)
            Text("SysGlanceが起動していません").font(.caption).multilineTextAlignment(.center)
            Text("クリックして起動").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: プロジェクトを生成してビルド**

Run:
```bash
cd ~/projects/sysglance && xcodegen generate && xcodebuild -project SysGlance.xcodeproj -scheme SysGlance -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | sort -u
```
Expected: `** BUILD SUCCEEDED **` のみ（error / warning なし）。`App/Info.plist` などが生成される。

- [ ] **Step 6: 起動して snapshot.json を確認**

Run:
```bash
cd ~/projects/sysglance && open build/Build/Products/Debug/SysGlance.app
```
40秒ほど待ってから:
```bash
python3 -c "
import json,os
d=json.load(open(os.path.expanduser('~/Library/Group Containers/FJW7DK8RB4.com.soshi.sysglance/snapshot.json')))
s=d['snapshot']; print(d['schemaVersion'], s['cpu'], s['memory']['pressure'], s['network'], s['disk'], [p['name'] for p in s['topProcesses'][:3]])"
```
Expected: `1 {'usage': 0.…} …` のように各値が入っている（`cpu` は2回目以降の書き出しで非 null）。

- [ ] **Step 7: ウィジェットを手動で確認**

1. デスクトップを右クリック →「ウィジェットを編集」→ 検索で「SysGlance」→ Small / Medium / Large を1つずつデスクトップに追加する。
2. 各サイズで値が表示され、下に「たった今」または「○分前」が出ることを確認する。
3. ウィジェットをクリック → SysGlance が前面に来る（この時点では詳細ウィンドウはまだ無いので、何も開かなくてよい）。
4. `pkill -f SysGlance.app/Contents/MacOS` で本体を止め、10分以上経ってからウィジェットが「SysGlanceが起動していません」になることを確認する（すぐ確かめたい場合は `snapshot.json` を一時的に削除し、ウィジェット編集で追加し直す）。
5. 確認後、本体を再度 `open` しておく。

- [ ] **Step 8: コミット**

```bash
cd ~/projects/sysglance && git add project.yml SharedUI App Widget && git commit -m "feat: add app sampling loop, shared layouts and WidgetKit widget

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 詳細ウィンドウと URL スキーム

**Files:**
- Create: `App/Detail/DetailWindowController.swift`, `App/Detail/DetailView.swift`
- Modify: `App/AppDelegate.swift`（全体を置き換え）

**Interfaces:**
- Consumes: `MetricsStore`（Task 7）、`CardModelBuilder`, `Fmt`（Core）、`Level.tint`, `Level.badgeSymbol`（SharedUI）
- Produces: `@MainActor DetailWindowController(store:)` の `show()`

- [ ] **Step 1: 詳細ウィンドウを作る**

`App/Detail/DetailWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class DetailWindowController {
    private let store: MetricsStore
    private var window: NSWindow?

    init(store: MetricsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "SysGlance"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: DetailView(store: store))
            window.setContentSize(NSSize(width: 880, height: 580))
            window.center()
            window.setFrameAutosaveName("SysGlanceDetail")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

`App/Detail/DetailView.swift`:

```swift
import Charts
import SwiftUI
import SysGlanceCore

struct DetailView: View {
    let store: MetricsStore
    @State private var selection: MetricKind? = .cpu

    var body: some View {
        NavigationSplitView {
            List(MetricKind.allCases, selection: $selection) { kind in
                Label(CardModelBuilder.title(of: kind), systemImage: CardModelBuilder.symbol(of: kind))
                    .tag(kind)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if let kind = selection {
                DetailPane(kind: kind, store: store)
            } else {
                ContentUnavailableView("項目を選択してください", systemImage: "sidebar.left")
            }
        }
    }
}

private struct DetailPane: View {
    let kind: MetricKind
    let store: MetricsStore

    var body: some View {
        let latest = store.latest
        let card = CardModelBuilder.card(kind, latest: latest, history: [], processLimit: 10)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.largeTitle.bold())
                    HStack(spacing: 6) {
                        Text(card.value).font(.title2.weight(.semibold)).monospacedDigit()
                        if let badge = card.level.badgeSymbol {
                            Image(systemName: badge).foregroundStyle(card.level.tint)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                let chart = ChartData.make(for: kind, history: store.history.elements)
                if !chart.series.isEmpty {
                    HistoryChart(data: chart)
                        .frame(height: 240)
                }
                Breakdown(kind: kind, latest: latest)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Chart

struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct ChartData {
    var series: [(name: String, points: [ChartPoint])]
    var yMax: Double?
    var format: (Double) -> String

    /// 30分 × 1Hz = 最大1800点。描画負荷を抑えるため最大360点程度に間引く。
    static func make(for kind: MetricKind, history: [MetricsSnapshot]) -> ChartData {
        let stride = max(1, history.count / 360)
        let sampled = Swift.stride(from: 0, to: history.count, by: stride).map { history[$0] }
        func line(_ name: String, _ value: (MetricsSnapshot) -> Double?) -> (name: String, points: [ChartPoint]) {
            (name, sampled.compactMap { s in value(s).map { ChartPoint(date: s.date, value: $0) } })
        }
        switch kind {
        case .cpu:
            return ChartData(series: [line("CPU") { $0.cpu?.usage }], yMax: 1, format: Fmt.percent)
        case .memory:
            return ChartData(series: [line("使用済み") { s in s.memory.map { Double($0.used) / Double(max($0.total, 1)) } }],
                             yMax: 1, format: Fmt.percent)
        case .network:
            return ChartData(series: [line("下り") { $0.network?.inbound }, line("上り") { $0.network?.outbound }],
                             yMax: nil, format: Fmt.rate)
        case .disk:
            return ChartData(series: [line("読み込み") { $0.diskIO?.inbound }, line("書き込み") { $0.diskIO?.outbound }],
                             yMax: nil, format: Fmt.rate)
        case .battery:
            return ChartData(series: [line("残量") { $0.battery?.level }], yMax: 1, format: Fmt.percent)
        case .system:
            return ChartData(series: [], yMax: nil, format: { _ in "" })
        }
    }
}

private struct HistoryChart: View {
    let data: ChartData
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(data.series, id: \.name) { series in
                ForEach(series.points) { point in
                    LineMark(x: .value("時刻", point.date), y: .value("値", point.value))
                        .foregroundStyle(by: .value("系列", series.name))
                        .interpolationMethod(.monotone)
                }
            }
            if let selectedDate {
                RuleMark(x: .value("時刻", selectedDate))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        tooltip(at: selectedDate)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...(data.yMax ?? max(observedMax, 1_000)))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(data.format(v)) }
                }
            }
        }
    }

    private var observedMax: Double {
        data.series.flatMap { $0.points.map(\.value) }.max() ?? 0
    }

    private func tooltip(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.hour().minute().second()).font(.caption2).foregroundStyle(.secondary)
            ForEach(data.series, id: \.name) { series in
                if let nearest = series.points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
                    Text("\(series.name) \(data.format(nearest.value))").font(.caption).monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Breakdown

private struct Breakdown: View {
    let kind: MetricKind
    let latest: MetricsSnapshot?

    var body: some View {
        switch kind {
        case .memory:
            if let m = latest?.memory {
                rows([
                    ("App メモリ", Fmt.bytes(m.app, base: .binary)),
                    ("確保されているメモリ（Wired）", Fmt.bytes(m.wired, base: .binary)),
                    ("圧縮", Fmt.bytes(m.compressed, base: .binary)),
                    ("キャッシュ", Fmt.bytes(m.cached, base: .binary)),
                    ("スワップ使用量", "\(Fmt.bytes(m.swapUsed, base: .binary)) / \(Fmt.bytes(m.swapTotal, base: .binary))"),
                    ("メモリプレッシャー", CardModelBuilder.pressureLabel(m.pressure)),
                ])
            }
        case .disk:
            if let d = latest?.disk {
                rows([
                    ("容量", Fmt.bytes(d.total, base: .decimal)),
                    ("使用済み", Fmt.bytes(d.used, base: .decimal)),
                    ("空き", Fmt.bytes(d.available, base: .decimal)),
                ])
            }
        case .battery:
            if let b = latest?.battery {
                rows([
                    ("残量", Fmt.percent(b.level)),
                    ("電源", b.isOnAC ? "電源アダプタ" : "バッテリー"),
                    ("状態", b.isCharging ? "充電中" : "充電していません"),
                ])
            } else {
                Text("このMacにはバッテリーがありません").foregroundStyle(.secondary)
            }
        case .system:
            VStack(alignment: .leading, spacing: 8) {
                if let uptime = latest?.uptime {
                    rows([("稼働時間", Fmt.duration(uptime))])
                }
                Text("メモリ使用量の多いプロセス").font(.headline).padding(.top, 8)
                Text("他のユーザー（システム）のプロセスは含まれません").font(.caption).foregroundStyle(.secondary)
                rows((latest?.topProcesses ?? []).map { ($0.name, Fmt.bytes($0.memory, base: .binary)) })
            }
        case .cpu, .network:
            EmptyView()
        }
    }

    private func rows(_ items: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                GridRow {
                    Text(item.0).foregroundStyle(.secondary)
                    Text(item.1).monospacedDigit()
                }
            }
        }
    }
}
```

- [ ] **Step 2: AppDelegate を置き換える（URL スキームと再オープン）**

```swift
import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let publisher = SnapshotPublisher()
    private lazy var detail = DetailWindowController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        store.start()
    }

    /// ウィジェットのタップ（sysglance://detail）
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "sysglance" }) {
            detail.show()
        }
    }

    /// Finder や Spotlight から再度起動されたときは詳細ウィンドウを開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        detail.show()
        return false
    }
}
```

- [ ] **Step 3: ビルドして確認**

Run:
```bash
cd ~/projects/sysglance && pkill -f SysGlance.app/Contents/MacOS; xcodebuild -project SysGlance.xcodeproj -scheme SysGlance -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | sort -u && open build/Build/Products/Debug/SysGlance.app && sleep 5 && open "sysglance://detail"
```
Expected: `** BUILD SUCCEEDED **`、詳細ウィンドウが開く。
手動確認:
- サイドバーで CPU / メモリ / ネットワーク / SSD / バッテリー / システムを切り替えられる
- CPU のグラフが1秒ごとに伸び、ホバーするとその時刻と値のツールチップが出る
- メモリに App / Wired / 圧縮 / キャッシュ / スワップ / プレッシャーの内訳が出る
- システムに稼働時間と上位10プロセスが出る
- ウィンドウを閉じてからデスクトップのウィジェットをクリックすると、再び詳細ウィンドウが開く

- [ ] **Step 4: コミット**

```bash
cd ~/projects/sysglance && git add App && git commit -m "feat(app): add detail window with history charts and URL scheme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: デスクトップパネル

**Files:**
- Create: `App/PanelSettings.swift`
- Create: `App/Panel/DraggablePanel.swift`, `App/Panel/DesktopPanelController.swift`, `App/Panel/PanelView.swift`
- Modify: `App/AppDelegate.swift`（全体を置き換え、最終版）

**Interfaces:**
- Consumes: `MetricsStore`（Task 7）、`DetailWindowController`（Task 8）、`LayoutSize`, `MetricsLayout`（SharedUI）、`CriticalSpring`, `EdgeSnap`, `CardModelBuilder`（Core）
- Produces: `@MainActor @Observable PanelSettings(defaults:)` の `size: LayoutSize`, `launchAtLogin`, `setLaunchAtLogin(_:)`, `panelOrigin: CGPoint?`；`DraggablePanel`（`onDragBegan`, `onDragEnded: (CGVector) -> Void`, `onDoubleClick`）；`DesktopPanelController(store:settings:openDetail:)` の `show()`；`PanelView(store:settings:openDetail:)`

- [ ] **Step 1: 設定を作る**

`App/PanelSettings.swift`:

```swift
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
```

- [ ] **Step 2: パネルを作る**

`App/Panel/DraggablePanel.swift`:

```swift
import AppKit

/// デスクトップに貼り付く枠なしパネル。ドラッグ移動を自前で処理し、離した瞬間の速度を通知する。
/// SwiftUI 側のジェスチャーだとウィンドウ移動中に座標系がずれるため、sendEvent で横取りしている。
final class DraggablePanel: NSPanel {
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((CGVector) -> Void)?
    var onDoubleClick: (() -> Void)?

    private static let dragThreshold: CGFloat = 3
    private static let velocityWindow: TimeInterval = 0.1

    private var mouseDownLocation: CGPoint?
    private var originAtMouseDown: CGPoint = .zero
    private var isDragging = false
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            mouseDownLocation = NSEvent.mouseLocation
            originAtMouseDown = frame.origin
            isDragging = false
            samples = []
            // 吸着アニメーション中でも掴んだ瞬間に止める（割り込み可能）
            onDragBegan?()
        case .leftMouseDragged:
            guard let start = mouseDownLocation else { break }
            let mouse = NSEvent.mouseLocation
            if !isDragging, hypot(mouse.x - start.x, mouse.y - start.y) < Self.dragThreshold { return }
            isDragging = true
            setFrameOrigin(CGPoint(x: originAtMouseDown.x + mouse.x - start.x,
                                   y: originAtMouseDown.y + mouse.y - start.y))
            samples.append((event.timestamp, mouse))
            samples.removeAll { event.timestamp - $0.time > Self.velocityWindow }
            return
        case .leftMouseUp:
            let wasDragging = isDragging
            mouseDownLocation = nil
            isDragging = false
            if wasDragging {
                onDragEnded?(releaseVelocity(at: event.timestamp))
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// 直近 0.1 秒の移動から求めた速度（pt/s）。止まってから離した場合は 0。
    private func releaseVelocity(at time: TimeInterval) -> CGVector {
        let recent = samples.filter { time - $0.time <= Self.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}
```

`App/Panel/DesktopPanelController.swift`:

```swift
import AppKit
import SwiftUI
import SysGlanceCore

@MainActor
final class DesktopPanelController: NSObject {
    static let screenMargin: CGFloat = 16

    private let panel: DraggablePanel
    private let hosting: NSHostingView<PanelView>
    private let settings: PanelSettings
    private var springX: CriticalSpring?
    private var springY: CriticalSpring?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(store: MetricsStore, settings: PanelSettings, openDetail: @escaping @MainActor () -> Void) {
        self.settings = settings
        panel = DraggablePanel(contentRect: CGRect(origin: .zero, size: settings.size.size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hosting = NSHostingView(rootView: PanelView(store: store, settings: settings, openDetail: openDetail))
        super.init()

        // 壁紙・デスクトップアイコンより上、通常ウィンドウより下
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        hosting.sizingOptions = []
        panel.contentView = hosting

        panel.onDragBegan = { [weak self] in self?.stopAnimation() }
        panel.onDragEnded = { [weak self] velocity in self?.settle(velocity: velocity) }
        panel.onDoubleClick = openDetail

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        let size = settings.size.size
        let origin = settings.panelOrigin.flatMap { saved in
            NSScreen.screens.contains { $0.visibleFrame.intersects(CGRect(origin: saved, size: size)) } ? saved : nil
        } ?? defaultOrigin(for: size)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        observeSize()
    }

    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visible.maxX - size.width - Self.screenMargin, y: visible.maxY - size.height - Self.screenMargin)
    }

    /// サイズ変更時は左上を固定して伸縮し、画面からはみ出したら吸着で戻す
    private func observeSize() {
        withObservationTracking {
            _ = settings.size
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let frame = self.panel.frame
                let size = self.settings.size.size
                self.panel.setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                                    display: true)
                self.settle(velocity: .zero)
                self.observeSize()
            }
        }
    }

    @objc private func screensChanged() {
        // ディスプレイが外れた等で画面外に出たパネルを戻す
        settle(velocity: .zero)
    }

    private func settle(velocity: CGVector) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var projected = panel.frame
        projected.origin.x += EdgeSnap.project(velocity: velocity.dx)
        projected.origin.y += EdgeSnap.project(velocity: velocity.dy)
        let target = EdgeSnap.target(for: projected, in: visible, margin: Self.screenMargin)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrameOrigin(target)
            settings.panelOrigin = target
            return
        }
        springX = CriticalSpring(position: panel.frame.minX, velocity: velocity.dx, target: target.x)
        springY = CriticalSpring(position: panel.frame.minY, velocity: velocity.dy, target: target.y)
        if displayLink == nil, let view = panel.contentView {
            let link = view.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTimestamp.map { now - $0 } ?? (1.0 / 60)
        lastTimestamp = now
        guard var x = springX, var y = springY else {
            stopAnimation()
            return
        }
        x.step(dt: dt)
        y.step(dt: dt)
        springX = x
        springY = y
        if x.isSettled && y.isSettled {
            let target = CGPoint(x: x.target, y: y.target)
            panel.setFrameOrigin(target)
            settings.panelOrigin = target
            stopAnimation()
        } else {
            panel.setFrameOrigin(CGPoint(x: x.position, y: y.position))
        }
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        springX = nil
        springY = nil
    }
}
```

`App/Panel/PanelView.swift`:

```swift
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
```

- [ ] **Step 3: AppDelegate を最終版に置き換える**

`App/AppDelegate.swift`:

```swift
import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let settings = PanelSettings()
    private let publisher = SnapshotPublisher()
    private lazy var detail = DetailWindowController(store: store)
    private var panel: DesktopPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        let panel = DesktopPanelController(store: store, settings: settings) { [weak self] in
            self?.detail.show()
        }
        panel.show()
        self.panel = panel
        store.start()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.stop() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.start(resetBaselines: true) }
        }
    }

    /// ウィジェットのタップ（sysglance://detail）
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "sysglance" }) {
            detail.show()
        }
    }

    /// Finder や Spotlight から再度起動されたときは詳細ウィンドウを開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        detail.show()
        return false
    }
}
```

- [ ] **Step 4: ビルドして表示を確認**

Run:
```bash
cd ~/projects/sysglance && pkill -f SysGlance.app/Contents/MacOS; xcodebuild -project SysGlance.xcodeproj -scheme SysGlance -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | sort -u && open build/Build/Products/Debug/SysGlance.app
```
Expected: `** BUILD SUCCEEDED **`。メイン画面の右上に Large サイズのガラスパネルが表示される（前回位置が保存されていればその位置）。

手動確認（すべて PASS であること）:
- パネルは壁紙とデスクトップアイコンの上、通常ウィンドウの下にある（Finder ウィンドウを重ねると隠れる）
- 別の Space（デスクトップ）に切り替えてもパネルが表示される
- 右クリック →「サイズ」で 小 / 中 / 大 を切り替えると、左上を固定して大きさが変わる。純正ウィジェットと同じ大きさ・同じレイアウトになる
- ドラッグで1:1に追従する。画面端の近くで離すと端から16ptの位置へ滑らかに吸着する。勢いよく投げると投げた方向へ流れてから止まる
- 吸着アニメーション中に再度掴むと、その場で止まって追従する
- ダブルクリックで詳細ウィンドウが開く
- 右クリック →「ログイン時に起動」をオンにすると、システム設定 > 一般 > ログイン項目 に SysGlance が出る（確認後オフに戻してよい）
- 値をアクティビティモニタと比較する: CPU 使用率、メモリ「使用済みメモリ」、スワップ使用領域、メモリプレッシャーの色、ディスクの読み書き（ディスクタブの「データの読み込み/秒」）、ネットワーク（「受信データ/秒」）が同じ桁で一致する
- システム設定 > アクセシビリティ > ディスプレイ で「視差効果を減らす」をオン → 吸着がアニメーションなしで即移動になる。「透明度を下げる」をオン → パネルが不透明な背景になる（確認後元に戻す）
- VoiceOver（⌘F5）でパネルにカーソルを当てると「メモリ 8.4 GB 使用、16.0 GB 中、プレッシャー正常」のように項目単位で読み上げる

- [ ] **Step 5: 常駐 CPU 使用率を計測（Review Focus 5）**

Run:
```bash
sleep 15; PID=$(pgrep -f SysGlance.app/Contents/MacOS | head -1); top -l 6 -s 5 -pid $PID -stats pid,cpu,mem | grep -E "^ *$PID"
```
Expected: 2行目以降の CPU 列の平均が 2.0 未満、メモリ列が増え続けない（20MB 前後で安定）。超える場合は `sample $PID 5` で `CGDrawingLayer` / `vSepConvolve` / `apply_blur` が出ていないか調べ、ぼかしやトランジションを足していないか確認する。

- [ ] **Step 6: 画面外の保存位置からの復帰を確認（Review Focus 1）**

Run:
```bash
pkill -f SysGlance.app/Contents/MacOS; defaults write com.soshi.sysglance panelOrigin -array 99999 99999 && open ~/projects/sysglance/build/Build/Products/Debug/SysGlance.app
```
Expected: パネルがメイン画面の右上に表示される（画面外に消えない）。

- [ ] **Step 7: コミット**

```bash
cd ~/projects/sysglance && git add App && git commit -m "feat(app): add desktop glass panel with widget-sized layouts and spring snapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: README と最終確認

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: 全タスクの成果物
- Produces: なし

- [ ] **Step 1: README を書く**

````markdown
# SysGlance

SSD・メモリ・CPU・ネットワーク・バッテリー・稼働時間を、デスクトップのガラスパネル（1秒更新）と
macOS の純正ウィジェットで表示する常駐アプリ。macOS 26 以降。

## ビルド

```bash
brew install xcodegen   # 未導入なら
xcodegen generate
xcodebuild -project SysGlance.xcodeproj -scheme SysGlance -configuration Release -derivedDataPath build -allowProvisioningUpdates build
cp -R build/Build/Products/Release/SysGlance.app /Applications/
open /Applications/SysGlance.app
```

ロジックのテスト:

```bash
cd Packages/SysGlanceCore && swift test
```

## 使い方

- パネル: ドラッグで移動、画面端に吸着。右クリックでサイズ（小/中/大）、詳細、ログイン時に起動、終了。ダブルクリックで詳細。
- ウィジェット: デスクトップを右クリック →「ウィジェットを編集」→「SysGlance」。更新は OS の予算内（数分おき）。クリックで詳細。
- 本体が止まっていると、10分後からウィジェットに「SysGlanceが起動していません」と出る。

## 構成

- `Packages/SysGlanceCore` — UI 非依存のロジック（計測・差分計算・フォーマット・表示モデル）
- `SharedUI` — パネルとウィジェット共通の SwiftUI レイアウト
- `App` — 常駐アプリ（パネル・詳細ウィンドウ・App Group への書き出し）
- `Widget` — WidgetKit 拡張

設計は `docs/superpowers/specs/2026-10-07-sysglance-design.md`。
````

- [ ] **Step 2: 全体検証**

Run:
```bash
cd ~/projects/sysglance/Packages/SysGlanceCore && swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning:|✘|Test run with"
cd ~/projects/sysglance && xcodegen generate && xcodebuild -project SysGlance.xcodeproj -scheme SysGlance -configuration Release -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|warning:|BUILD" | sort -u
git status --short
```
Expected: `✔ Test run with 69 tests in 12 suites passed`、`** BUILD SUCCEEDED **`、`git status` は README.md のみ。

- [ ] **Step 3: コミット**

```bash
cd ~/projects/sysglance && git add README.md && git commit -m "docs: add README with build and usage

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
