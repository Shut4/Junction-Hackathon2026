# 歩響ナビ

視覚障害者の移動を支援する、iPhoneアプリと振動する白杖の試作品です。目的地への道案内を音声で伝え、カメラで検出した危険・注意を画面と振動で知らせます。VoiceOverでの操作を想定しています。

## できること

- **道案内：** 目的地を検索し、登録された通行不可区間を避ける経路を表示。地図・カメラ画面でナビ音声を利用できます。
- **危険の通知：** カメラと深度から障害物や段差を検出。危険・注意の自動読み上げは行わず、振動で通知し、ナビ音声を優先します。
- **白杖との連携：** XIAOへBluetoothで頭の高さの障害物の状態を送り、注意と危険を異なる振動リズムで伝えます。

経路案内の対応範囲は、保存済み道路データのある**北九州市・小倉駅周辺と戸畑区**です。地域をまたぐ経路には対応していません。施設入口までの通行可能性や安全を保証するものではなく、同行者のいる環境で評価する試作品です。

## 使い方

1. 初回起動時に位置情報・カメラを許可します。通知の許可は任意です。
2. 検索欄から目的地を選び、経路を確認して「ナビ開始」または「カメラ案内」を選びます。
3. 通れない道路は「通行不可登録」から登録します。報告は端末内に保存されます。

白杖を使う場合は、下記のArduinoコードを書き込み、アプリの「設定 → 白杖 Bluetooth」から検索・接続します。

## iPhoneアプリを動かす

macOS・Xcodeと、iOS 26以降のiPhoneを使用します。シミュレーターでは画面操作を確認でき、実際のカメラ・深度・振動の確認には対応する実機が必要です。

1. このリポジトリを取得します。

   ```sh
   git clone https://github.com/Shut4/Junction-Hackathon2026.git
   cd Junction-Hackathon2026
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

2. `Config/Local.xcconfig` の `JG_TEAM` と `JG_BUNDLE_ID` を自分の署名情報へ変更します。このファイルはGitの管理対象外です。
3. 物体認識用のCore MLモデルを用意し、次を実行します。モデルはリポジトリに含まれません。取得・利用条件は[モデルの説明](Docs/MODEL.md)を参照してください。

   ```sh
   Scripts/install_model.sh /path/to/vidvipo_yolov8x_2023-05-19.mlmodel
   ```

   モデルなしでビルドする場合は、代わりに `python3 Scripts/create_project.py` を実行します。
4. `JunctionGuide.xcodeproj` をXcodeで開き、Schemeを **JunctionGuide**、実行先をiPhoneまたはシミュレーターにして実行します。

## Arduinoコード

[**Firmware/CaneVibePower/CaneVibePower.ino**](Firmware/CaneVibePower/CaneVibePower.ino) をGitで管理しています。XIAO nRF52840とDRV2605L・LRAを使用する、BLE通信と電源ボタン付きのスケッチです。

Arduino IDEでこのファイルを開いて書き込みます。必要なボード・ライブラリ・配線は[書き込み手順](Firmware/CaneVibePower/README.md)を参照してください。変更時はこのリポジトリ内のファイルを更新します。

## 構成・詳細

| 場所 | 内容 |
|---|---|
| `App/`・`Core/` | iPhoneの画面・カメラ・経路検索・音声・Bluetooth |
| `Firmware/` | 白杖のArduinoコードとテスト |
| `Data/` | 対応地域の道路データ |
| `Tests/`・`Scripts/` | テストと開発用スクリプト |
| `Docs/` | 詳しい仕様・検証記録 |

アプリのコアテストは `swift test` で実行できます。

- [白杖とのBluetooth連携](Docs/BLUETOOTH.md)
- [道路データ](Docs/DATA.md)
- [モデルと利用条件](Docs/MODEL.md)
- [検証記録・未確認項目](Docs/VALIDATION.md)
