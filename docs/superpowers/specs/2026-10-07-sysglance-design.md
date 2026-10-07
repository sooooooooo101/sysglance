# SysGlance 設計書

- 日付: 2026-10-07
- 状態: ブレインストーミングで合意済み（セクション1〜4承認）。試作検証（2026-10-07）を反映し §10 の変更を加えた

## 1. 目的

自分のMac（macOS 26）で、SSD・メモリを中心としたシステム稼働状況を**デスクトップ上で常に**確認できるようにする。

- デスクトップで概要を見たい → WidgetKit ウィジェット（OS予算内で更新）
- 詳しく見たいとき → アプリを開く／ウィジェットのタップで開く詳細ウィンドウ（1秒更新・30分グラフ）
- （当初あったデスクトップ貼り付けパネルは §12 で削除）

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
  ├─ SharedUI（ウィジェットのレイアウト: LayoutSize / MetricsLayout）
  └─ DetailWindow（通常ウィンドウ、Swift Charts）
SysGlanceWidget.appex（WidgetKit、App Sandbox 有効）
  └─ snapshot.json を読んで Small/Medium/Large を表示、タップで sysglance://detail
```

- 計測は1秒間隔。プロセス一覧は5秒間隔、SSD空き容量は30秒間隔（空き容量計算はパージ可能領域の集計を伴い重いため）。常駐時CPU使用率 2% 未満（試作実測 1.1〜1.9%）。
- ウィジェットのタイムライン再読込は「前回から5分以上経過」または「メモリプレッシャー段階の変化」時のみ。
- 外部依存なし（Swift Charts 等の標準フレームワークのみ）。
- 起動は SwiftUI App ではなく AppKit（`main.swift` + `AppDelegate`）。常駐・独自ウィンドウ・URLスキーム受信を素直に扱うため。
- プロジェクト生成は **XcodeGen（`project.yml`）** を使う（開発ツールのみ、製品依存ではない）。※ブレストでは「XcodeGenを使わない」としていたが、再現性と計画記述性のため変更。`.xcodeproj` はコミットしない。

### 識別子・環境

- 配置: `~/projects/sysglance`
- Team ID: `FJW7DK8RB4`
- アプリ: `com.soshi.sysglance` / ウィジェット: `com.soshi.sysglance.widget`
- App Group: `FJW7DK8RB4.com.soshi.sysglance`
- URLスキーム: `sysglance://detail`
- Deployment target: macOS 26.0、Swift 6（言語モード6）

## 4. UI / インタラクション（apple-design 準拠）

### ウィジェットのサイズ

| サイズ | 内容 |
|---|---|
| Small | CPU・メモリのリング |
| Medium | CPU / メモリ / SSD / ネットワークの 2×2 |
| Large | 全項目の縦リスト＋SSD読み書き・上位3プロセス |

- 数値は `monospacedDigit()`。`contentTransition(.numericText())`・`Canvas`・ぼかしは使わない（試作で常駐CPUが約20%になったため）。
- 色は単色基調。状態色は警告時のみ（メモリプレッシャー黄/赤、SSD空き10%未満、バッテリー20%未満で非充電）。色に加えアイコン（⚠︎/⛔︎）で示す。

### 起動とウィンドウ
- アプリを開く（Finder / Spotlight / 再度の起動）と詳細ウィンドウを表示。ログイン項目として自動起動したときは表示せず裏で計測のみ。
- 詳細ウィンドウを閉じても本体は常駐し、ウィジェット用の書き出しを続ける（Dock 非表示）。
- 詳細ウィンドウが見えていない間（閉じた・隠れた）は SwiftUI の表示を外し、見えたら作り直す（常駐CPUを抑えるため）。選択中の項目は保持。
- 詳細ウィンドウのツールバー右の歯車メニュー: ログイン時に起動、SysGlance を終了。

### 詳細ウィンドウ
- サイドバー（項目一覧）＋右に30分グラフ（Swift Charts）と内訳。
- メモリ: App / Wired / 圧縮 / キャッシュ、スワップ。システム: 上位10プロセス。
- グラフはホバーでその時点の値を表示。

### 純正ウィジェット
- Small / Medium / Large（上表のレイアウト、スパークラインなし）。下部に「○分前」。
- `capturedAt` が10分以上古い、またはファイルが無い・読めないと「SysGlanceが起動していません」。
- タップで `sysglance://detail`（本体が起動していなければ起動して詳細ウィンドウ）。

### アクセシビリティ
- VoiceOver: 各カードを1要素に結合し「メモリ 12.3 GB 使用、16.0 GB 中、プレッシャー正常」形式で読み上げ。スパークラインは読み上げ対象外。

UI文言は日本語。

## 5. データフロー

```
Timer(1s) → SamplingEngine(actor).sample() → MetricsSnapshot（不変・Codable）
  → MetricsStore.append()（MainActor, @Observable）→ 詳細ウィンドウ再描画（見えている間のみ）
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
- ビルド: `xcodebuild -scheme SysGlance build` 成功、警告なし（警告はエラー扱い）。
- 実機チェック: 起動で詳細ウィンドウのみ表示、アクティビティモニタとの値比較、ウィジェット追加・表示・タップで詳細、本体停止時のウィジェット表示、ログイン時起動（ウィンドウを出さない）、詳細ウィンドウが見えていないときの常駐CPU<2%。

## 9. スコープ外

長期履歴保存、温度・ファン、GPU、アラート通知、配布用公証。

## 10. 試作検証による変更（2026-10-07）

| 項目 | 当初 | 変更後 | 理由 |
|---|---|---|---|
| パネル形状 | 幅320ptの縦リスト、項目ごとに表示/非表示 | 純正ウィジェットと同じ Small/Medium/Large、サイズで内容が決まる | ユーザー判断（ウィジェット機能に沿う） |
| 数値トランジション | `numericText` | なし | 常駐CPU 約20%の主因 |
| スパークライン | `Canvas` | `Shape` | CPU ラスタライズ回避 |
| SSD空き容量 | 毎秒 | 30秒間隔 | 取得が重い |
| 常駐CPU目標 | <1% | <2% | 1Hz再描画の下限（実測 1.1〜1.9%） |
| プロジェクト生成 | Xcode 直接 | XcodeGen | 再現性・計画記述性 |

## 11. 実装レビューによる変更（2026-10-07、Product Owner 承認待ち）

| 項目 | 変更前 | 変更後 | 理由 |
|---|---|---|---|
| ウィジェット再読込の最短間隔 | 5分 | 15分 | 5分（最大288回/日）は WidgetKit の1日予算（目安40〜70回）を超え、超過後は更新が止まる |
| 鮮度判定（起動していない表示） | 10分 | 45分 | 予算により再読込が間引かれると、動作中でも「起動していません」と誤表示されるため |
| ネットワークの除外IF | lo, utun, awdl, llw, bridge, anpi, gif, stf | 左記 + ipsec, ppp, ap, vmenet | 標準VPN（IKEv2/L2TP）・インターネット共有・VMの通信が物理IFと二重計上されるため |

## 12. デスクトップパネルの削除（2026-10-07、Product Owner 判断）

アプリを開くとパネルが出るのを避けたいという判断により、デスクトップパネルを機能ごと削除した（純正ウィジェット＋詳細ウィンドウのみ）。§4 の旧パネル仕様（ドラッグ・吸着・スプリング・サイズ選択・スパークライン）と §10 のパネル関連行は無効。関連コード（DesktopPanel, DraggablePanel, PanelSettings, Sparkline, CriticalSpring, EdgeSnap, PanelPlacement, DragTracker）は削除済み。
