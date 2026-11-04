# XIAO nRF52840 / DRV2605L BLEファームウェア

`CaneVibe/CaneVibe.ino` は提示されたLRAテストスケッチに、iOSアプリと同じBLEプロトコルv1を追加したものです。`CaneControl.h` も同じフォルダに置いたまま使用してください。既存の `feature/akiyoshi/xiao-cane-bluetooth` ブランチに追加しています。

## 危険度と振動

| iOSからの状態 | DRV2605Lの動作 |
|---|---|
| 0 検出なし | 停止 |
| 1 注意 | 300ms振動 → 1700ms停止（ゆっくりした単発） |
| 2 危険 | 120ms振動を100msの停止を挟んで3回 → 440ms停止（1秒周期） |
| 3 検知不能 | 停止 |
| 新しい有効指示が1000ms届かない | 停止・検知不能、StatusのTTL切れbitを立てる |
| BLE切断 | 停止・検知不能、sequence基準を初期化 |

注意は「ブー……」、危険は「ブッ・ブッ・ブッ……」という異なるリズムにしています。実機での区別しやすさは利用者による確認が必要です。危険状態は有効指示が更新される間継続します。BLE駆動には「10回で終了」という上限を設けず、解除状態またはTTL切れで止めます。同じ状態の再送では周期をリセットしません。

振動強度 `VIBRATION_LEVEL=0x75`、`drv.useLRA()`、RTPモードを提示スケッチから維持しています。元の「0x40まで」というコメントと実際の0x75が不一致だったため、コメントを実値に合わせました。LRAの定格やDRV2605Lの電圧・校正設定は今回のソフトウェア検証には含みません。

起動8秒後の自動テストは `ENABLE_AUTO_TEST=false` で無効にしました。未接続時のシリアル `t` / `T` は元と同じ10回のテスト、終了後10秒の休止です。`s` / `S` で停止できます。BLE接続時はローカルテストを中止し、以後はiOS側の指示を優先します。接続中に `s` を送った場合は、指示の再受信で即再駆動しないよう接続を解除します。

## Arduino IDEで書き込む

1. ボードマネージャーで **Seeed nRF52 Boards** を使用し、**Seeed XIAO nRF52840** を選択します。このコードは `bluefruit.h` を使用する非mbed版です。Senseの場合は対応するSenseボードを選択してください。
2. ライブラリ **Adafruit DRV2605 Library** と依存の **Adafruit BusIO** を用意します。Bluefruitは上記ボードパッケージに付属します。
3. `CaneVibe/CaneVibe.ino` を開きます。同じフォルダの `CaneControl.h` も必要です。
4. USB接続したXIAOのポートを選び、検証・書き込みを行います。
5. シリアルモニターを115200bpsで開き、`DRV2605L ready. BLE advertising: CaneVibe-01` を確認します。DRV2605Lが検出できない場合はBLE広告を開始しません。
6. iOSアプリの「設定 → XIAO Bluetooth → XIAOを検索」から `CaneVibe-01` へ接続します。
7. iOSの「危険の振動を試す（3連続）」で振動、「テストを終了」で停止を確認します。危険テストは1秒で3連続の振動が1組、注意テストは300msの単発が1回になる想定です。
8. カメラ案内では頭の高さの障害物検知から自動送信します。注意と危険の振動周期の違い、警告OFF、切断、通信途絶による停止をそれぞれ確認してください。

この試作のGATT書き込みは暗号化・認証を必須にしていません。接続先選択や受理Statusだけでは、認証済みの機器制御やモーター実振動の証明にはなりません。

## 実装と確認範囲

- UUIDとCommand/Statusの形式は `Docs/BLUETOOTH.md` および `Core/CaneProtocol.swift` と一致します。
- 10バイト長、version、state、TTL、予約ビット／バイト、検出なし・検知不能の未知距離を検証します。重複・古いsequenceでは状態も期限も更新しません。正常なuint16周回は受理します。
- `millis()`差分でTTLと振動を処理し、長い `delay()` で受信・停止を妨げません。
- BLEコールバックはイベントをFreeRTOSキューに渡します。I2Cと状態更新はloopだけで実行します。キューあふれ時は停止・切断して、基板のリセットを待ちます。
- Statusのoffset 3は元のGPIO3出力欄です。このFWはGPIO3を使用しないため0で固定しています。モーターの振動状態を示すものではありません。
- Statusには採用状態、最終sequence、TTL切れ／不正指示フラグ、uptimeを返します。各受信処理時と1秒周期で更新し、Notify送信失敗時は最新状態を再送します。
- ローカル環境の **Seeeduino nrf52 1.1.13 / Seeed XIAO nRF52840** 向けにコンパイル確認しています。実機への書き込み・BLE接続・実際の振動は未確認です。

制御ロジックのホストテスト：

```sh
clang++ -std=c++11 -Wall -Wextra -Werror Firmware/Tests/CaneControlTests.cpp -o /tmp/cane-control-tests
/tmp/cane-control-tests
```

確認内容：Swiftと共通の危険パケット、状態と振動周期、再送時の位相維持、TTL、sequenceの周回・重複・逆行、無効パケット、処理待ちの古い指示、millis周回、Statusのバイト順。

参考：[Seeed公式 Bluetooth Usage](https://wiki.seeedstudio.com/XIAO-BLE-Sense-Bluetooth_Usage/)、[Adafruit BLECharacteristic](https://learn.adafruit.com/bluefruit-nrf52-feather-learning-guide/blecharacteristic)。
