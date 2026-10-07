# SysGlance

SSD・メモリ・CPU・ネットワーク・バッテリー・稼働時間を、macOS の純正ウィジェットと
詳細ウィンドウ（1秒更新・30分グラフ）で表示する常駐アプリ。macOS 26 以降。

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

- アプリを開くと詳細ウィンドウが開く。閉じても裏で動き続け、ウィジェットに値を届ける。
- 詳細ウィンドウ右上の歯車メニューから「ログイン時に起動」と「終了」。ログイン時の自動起動ではウィンドウは開かない。
- ウィジェット: デスクトップを右クリック →「ウィジェットを編集」→「SysGlance」。更新は OS の予算内（数分おき）。クリックで詳細。
- 本体が止まっていると、45分後からウィジェットに「SysGlanceが起動していません」と出る（OS がウィジェット更新を間引いても誤表示しないよう長めにしている）。

## 構成

- `Packages/SysGlanceCore` — UI 非依存のロジック（計測・差分計算・フォーマット・表示モデル）
- `SharedUI` — ウィジェットの SwiftUI レイアウト
- `App` — 常駐アプリ（詳細ウィンドウ・App Group への書き出し）
- `Widget` — WidgetKit 拡張

設計は `docs/superpowers/specs/2026-10-07-sysglance-design.md`。
