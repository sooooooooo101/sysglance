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
- 本体が止まっていると、45分後からウィジェットに「SysGlanceが起動していません」と出る（OS がウィジェット更新を間引いても誤表示しないよう長めにしている）。

## 構成

- `Packages/SysGlanceCore` — UI 非依存のロジック（計測・差分計算・フォーマット・表示モデル）
- `SharedUI` — パネルとウィジェット共通の SwiftUI レイアウト
- `App` — 常駐アプリ（パネル・詳細ウィンドウ・App Group への書き出し）
- `Widget` — WidgetKit 拡張

設計は `docs/superpowers/specs/2026-10-07-sysglance-design.md`。
