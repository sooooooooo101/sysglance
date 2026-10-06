# SysGlance 設計書

- 日付: 2026-10-07
- 状態: ブレインストーミングで合意済み（セクション1〜4承認）

## 1. 目的

自分のMac（macOS 26）で、SSD・メモリを中心としたシステム稼働状況を**デスクトップ上で常に**確認できるようにする。

- リアルタイム（1秒更新）で見たい → デスクトップに貼り付くパネル
- 純正ウィジェットでも概要を見たい → WidgetKit ウィジェット（OS予算内で更新）
- 詳しく見たいとき → ウィジェットのタップ／パネルから開く詳細ウィンドウ

利用者は本人のみ。配布・公証はしない。

## 2. 表示項目

| 項目 | 内容 | 取得元（公開API） |
|---|---|---|
| CPU | 全体使用率 % | `host_statistics(HOST_CPU_LOAD_INFO)` の tick 差分 |
| メモリ | 使用量（App+Wired+圧縮）/ 総量、内訳、メモリプレッシャー、スワップ使用量 | `host_statistics64(HOST_VM_INFO64)`、`sysctl kern.memorystatus_vm_pressure_level`、`sysctl vm.swapusage` |
| SSD容量 | 内蔵起動ボリュームの使用量 / 空き | `URLResourceValues`（`volumeAvailableCapacityForImportantUsage`） |
| SSD読み書き | 読み / 書き 速度（B/s） | IOKit `IOBlockStorageDriver` の `Statistics`（親の `Physical Interconnect Location == "Internal"` のみ） |
| ネットワーク | 下り / 上り 速度（B/s） | `sysctl NET_RT_IFLIST2`（64bitカウンタ）。loopback と `utun` `awdl` `llw` `bridge` `anpi` `gif` `stf` 接頭辞のIFは除外 |
| バッテリー | 残量 %、充電中、残り時間 | `IOPSCopyPowerSourcesInfo`。内蔵バッテリーがなければ非表示 |
| システム | 稼働時間、メモリ使用量上位プロセス | `sysctl kern.boottime`、`proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V4).ri_phys_footprint`（取得できたプロセスのみ） |

メモリプレッシャー: `1=正常(緑)`, `2=警告(黄)`, `4=危険(赤)`。

## 3. 構成

```
SysGlance.app（LSUIElement 常駐、App Sandbox 無効）
  ├─ SysGlanceCore（ローカルSwift Package、UI非依存・テスト対象）
  │    Model / Math / Format / Shared / System(Readers) / Engine
  ├─ MetricsStore（@Observable、1800点＝30分のリングバッファ）
  ├─ SnapshotPublisher（30秒ごとに App Group へ snapshot.json）
  ├─ DesktopPanel（デスクトップレベルの NSPanel + SwiftUI）
  └─ DetailWindow（通常ウィンドウ、Swift Charts）
SysGlanceWidget.appex（WidgetKit、App Sandbox 有効）
  └─ snapshot.json を読んで Small/Medium/Large を表示、タップで sysglance://detail
```

- 計測は1秒間隔、プロセス一覧のみ5秒間隔。常駐時CPU使用率 1% 未満を目標。
- ウィジェットのタイムライン再読込は「前回から5分以上経過」または「メモリプレッシャー段階の変化」時のみ。
- 外部依存なし（Swift Charts 等の標準フレームワークのみ）。
- プロジェクト生成は **XcodeGen（`project.yml`）** を使う（開発ツールのみ、製品依存ではない）。※ブレストでは「XcodeGenを使わない」としていたが、再現性と計画記述性のため変更。`.xcodeproj` はコミットしない。

### 識別子・環境

- 配置: `~/projects/sysglance`
- Team ID: `FJW7DK8RB4`
- アプリ: `com.soshi.sysglance` / ウィジェット: `com.soshi.sysglance.widget`
- App Group: `FJW7DK8RB4.com.soshi.sysglance`
- URLスキーム: `sysglance://detail`
- Deployment target: macOS 26.0、Swift 6（言語モード6）

## 4. UI / インタラクション（apple-design 準拠）

### デスクトップパネル
- 幅320pt、Liquid Glass（`glassEffect(.regular, in: .rect(cornerRadius: 22))`）。
- 縦並びカード: CPU → メモリ → ネットワーク → SSD（読み書き＋容量）→ バッテリー → システム（稼働時間＋上位3プロセス）。
- 各カード: 現在値 + 直近2分（120点）のスパークライン。
- 数値は `monospacedDigit()` + `contentTransition(.numericText())`。
- 色は単色基調。状態色は警告時のみ（メモリプレッシャー黄/赤、SSD空き10%未満、バッテリー20%未満で非充電）。色に加えアイコン・文言で示す。
- ウィンドウレベルは `desktopIconWindow + 1`（壁紙・アイコンの上、通常ウィンドウの下）。全Spacesに表示（`.canJoinAllSpaces, .stationary, .ignoresCycle`）。
- ドラッグで移動。離したとき画面端から24pt以内なら端（マージン16pt）へ吸着。吸着は臨界減衰スプリング（damping 1.0, response 0.35）で、離した瞬間の速度を引き継ぐ。位置は UserDefaults に保存。
- 右クリックメニュー: 項目の表示/非表示、詳細ウィンドウを開く、ログイン時に起動、終了。

### 詳細ウィンドウ
- サイドバー（項目一覧）＋右に30分グラフ（Swift Charts）と内訳。
- メモリ: App / Wired / 圧縮 / キャッシュ、スワップ。システム: 上位10プロセス。
- グラフはホバーでその時点の値を表示。

### 純正ウィジェット
- Small: CPU・メモリのリング。Medium: CPU / メモリ / SSD容量 / ネットワーク。Large: 全項目＋上位3プロセス。
- 「○分前」表示。`capturedAt` が10分以上古いと「SysGlanceが起動していません」。

### アクセシビリティ
- Reduce Motion: スプリング吸着・数値トランジションを無効化（即時移動 / クロスフェード）。
- Reduce Transparency: ガラスを不透明背景（`windowBackgroundColor`）に置換。
- VoiceOver: 各カードを1要素に結合し「メモリ 12.3ギガバイト使用、プレッシャー正常」形式で読み上げ。

UI文言は日本語。

## 5. データフロー

```
Timer(1s) → SamplingEngine(actor).sample() → MetricsSnapshot（不変・Codable）
  → MetricsStore.append()（MainActor, @Observable）→ パネル / 詳細ウィンドウ再描画
  → 30秒毎: SnapshotFile.write（atomic）→ 条件付き WidgetCenter.reloadAllTimelines()
```

- 履歴はメモリ上のみ（再起動でリセット）。
- `snapshot.json`: `schemaVersion`（=1）, `capturedAt`, スナップショット本体。

## 6. エラー処理

- 各Readerは失敗時 `nil`、その項目のみ「—」表示。全体は停止しない。
- 累積カウンタが前回より減少（スリープ復帰・IF再接続等）→ その回の速度は0。経過時間0以下も0。初回は基準取得のみ（速度0）。
- スリープ中はタイマー停止、復帰後最初の計測は基準取り直し。
- バッテリー無しMacではバッテリーカード非表示。
- JSON読込失敗時、ウィジェットはプレースホルダー表示。

## 7. セキュリティ・プライバシー

- ネットワーク通信なし。外部送信なし。
- プロセス名は端末内のみ。snapshot.json は App Group コンテナ内。
- 本体は Sandbox 無効（プロセス一覧・IOKit のため）、ウィジェットは Sandbox 有効。

## 8. テストと完了条件

- 単体テスト（`swift test`、SysGlanceCore）: カウンタ差分（通常/巻き戻り/経過0/初回）、CPU%（0〜100）、プレッシャー段階・容量/バッテリー閾値、リングバッファ（上限1800・古い順破棄）、snapshot往復・鮮度判定、単位フォーマット、スプリング・吸着計算、実機Readerのスモークテスト。
- ビルド: `xcodebuild -scheme SysGlance build` 成功、警告なし。
- 実機チェック: パネルのレベルと全Spaces表示、アクティビティモニタとの値比較、ウィジェット追加・表示・タップで詳細、ログイン時起動、Reduce Motion / Transparency、常駐CPU<1%。

## 9. スコープ外

長期履歴保存、温度・ファン、GPU、アラート通知、配布用公証。
