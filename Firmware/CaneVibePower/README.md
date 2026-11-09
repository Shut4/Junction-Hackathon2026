# CaneVibePower：電源ボタン付き白杖

iPhoneからBluetoothで状態を受け取り、DRV2605LとLRAで振動を伝えるArduinoスケッチです。**`CaneVibePower.ino` 1ファイル**で使用できます。

## 用意するもの

- Seeed Studio XIAO nRF52840（Senseも使用可能）
- DRV2605L、LRA、D0に接続する押しボタン
- Arduino IDEとUSBケーブル

## 書き込み

1. Arduino IDEのボードマネージャーで **Seeed nRF52 Boards** をインストールします。mbed版ではありません。
2. ボードは **Seeed XIAO nRF52840** を選びます。Senseの場合は **Seeed XIAO nRF52840 Sense** を選びます。
3. ライブラリマネージャーで **Adafruit DRV2605 Library** と **Adafruit BusIO** をインストールします。Bluefruit/TinyUSBはボードパッケージに付属します。
4. このフォルダの `CaneVibePower.ino` を開き、XIAOをUSB接続してポートを選び、検証・書き込みを実行します。
5. iPhoneアプリの「設定 → 白杖 Bluetooth」から **CaneVibe-01** を検索・接続し、振動テストを行います。

配線は、ボタンが **D0–GND**（内蔵プルアップ）、DRV2605LのI²Cが **D4/SDA・D5/SCL** です。LRAはDRV2605Lの **OUT+・OUT−** へ接続します。振動の出力設定は使用するLRAの仕様に合わせて確認してください。

## 動作

| 操作・状態 | 結果 |
|---|---|
| 動作中にボタンを1回押して離す | 振動・BLEを止めてSystem OFFへ移行 |
| System OFF中にボタンを押す | 再起動。アプリから再接続する |
| 注意 | 300msの単発振動を2秒周期で繰り返す |
| 危険 | 120msの振動を3連続、1秒周期で繰り返す |
| 検出なし・検知不能・BLE切断・指示が1秒途絶 | 振動を停止 |

System OFFは省電力停止であり、電池の物理的な切り離しではありません。実機での電源復帰・消費電流・振動の確認は別途必要です。

通信仕様は[Bluetooth連携](../../Docs/BLUETOOTH.md)、制御ロジックのテストは[Firmwareの説明](../README.md)を参照してください。
