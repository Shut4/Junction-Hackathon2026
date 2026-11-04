# BLE共通仕様案 v0.1

**状態：今回の共有用に作成した提案。未実装。B（iOS BLE）とC（FW）が同じ版へ固定して使用する。**

## 1. GATT

| 項目 | 値・属性 |
|---|---|
| Local name | `CaneVibe-01` |
| Service | `77D6F146-E62C-4ED3-BAAA-6C1526D79D28` |
| Command characteristic | `BC6B696D-E8D3-4566-9730-EA6B057EE324` / Write with response |
| Status characteristic | `D9B72442-A4CC-4E98-9352-CED78C12B22F` / Read + Notify |
| Central / Peripheral | iPhone / XIAO ESP32C3 |
| 数値のバイト順 | 複数バイトの整数は全てLittle Endian |
| プロトコル版 | パケット内version=1（文書版v0.1と区別） |

上記128-bit UUIDは今回の試作のために新規生成した値。既存の標準サービスではない。両側で同じ値を使う。
接続時はサービスを探索、StatusのNotifyを有効化、最初はUNAVAILABLEを送る。サービス／属性が一致しなければ自動駆動しない。

## 2. Command：10バイト

| Offset | 長さ | 名前 | 値 |
|---|---|---|---|
| 0 | 1 | version | 1 |
| 1 | 1 | state | 0=CLEAR（検出なし）、1=CAUTION、2=DANGER、3=UNAVAILABLE |
| 2 | 2 | sequence | uint16。新しい指示ごとに+1、65535の次は0 |
| 4 | 2 | ttl_ms | uint16。初期版は1000だけを受理 |
| 6 | 2 | distance_mm | 0〜65534。未取得は65535（FF FF）。危険度判定はスマホ側 |
| 8 | 1 | flags | bit0=床高さが深度から推定された、bit1=手動テスト、bit2〜7=0 |
| 9 | 1 | reserved | 0 |

距離は補助情報。FWは距離からstateを再計算しない。CLEAR/UNAVAILABLEのdistanceはFF FFとする。手動テスト時も同じバイト形式を使い、flags bit1を立てる。

### iOS送信側

- 250ms周期を提案。状態が変わったら送信を優先する。送信直前に最新の検知可能状態と深度の鮮度を確認する。
- 1つのWriteが処理中なら次の状態は最新1件だけ保持し、古い中間状態を積まない。
- 音声の再通知タイマーと独立させる。同じ状態を再送するときも新しいsequenceを使う。
- 600msより古い有効深度、明示的カメラエラー、無効姿勢、カメラ停止、背景移行、警告機能OFFはUNAVAILABLEとする。OFFをCLEARと表現しない。
- 有効な深度で2フレーム連続した注意／危険を採用する案。CLEARも有効な検出なし2フレームで採用。無効な結果で継続回数を進めない。250ms再送も検知フレーム数に数えない。
- UNAVAILABLEは継続判定を待たず即時。新しい有効状態になるまでは過去の危険度を再利用しない。
- 閾値・連続判定・TTLは試作値であり、反応時間の保証ではない。

### FW受信側

1. 長さ10、version=1、state範囲、ttl=1000、予約ビット／バイトを検証。不正は状態と受信期限を更新しない。
2. 接続ごとにsequenceの基準を初期化。初回は受理。
3. 2回目以降は`delta=(new-old) mod 65536`で、1〜32767だけを新規受理。同一seqは重複、32768〜65535は古いとして駆動状態も期限も更新しない。
4. 受理した時点の単調増加時刻を保存し、受理stateへ移行。同じstateなら振動パターンの位相はリセットせず、期限だけ更新。
5. 更新から1000ms経過、またはBLE切断を検出したら危険振動を停止し、UNAVAILABLEへ。
6. 古いパケットの再到着を新しい指示として扱わない。Write responseはBLE層の応答で、実振動の検出を意味しない。

電源再投入・接続直後のGPIOはLOW。手動テストから自動へ戻す際はUNAVAILABLEを経由する。暗号化／Bondingは未決定なので、公開環境で認証済み制御ができる仕様とは扱わない。

## 3. Status：10バイト

| Offset | 長さ | 名前 | 値 |
|---|---|---|---|
| 0 | 1 | version | 1 |
| 1 | 1 | applied_state | 現在FWが採用している0〜3のstate |
| 2 | 1 | error_flags | bit0=TTL切れ、bit1=不正パケット検出。以降0 |
| 3 | 1 | gpio_level | 現在のGPIO3出力、0=LOW／1=HIGH |
| 4 | 2 | last_sequence | 最後に受理したsequence。未受理時は0＋state=UNAVAILABLE |
| 6 | 4 | uptime_ms | uint32、FW起動からの単調増加時刻。約49.7日で周回 |

- 有効Command受理時、状態変更時、不正パケット受信時、接続中のTTL切れ時にNotifyする。
- `last_sequence`は受理確認用。`gpio_level`はGPIO出力の状態であり、モーターの実振動を検出した値ではない。
- 不正パケットフラグは次の有効Command受理でクリア。TTL切れも次の有効Command受理でクリア。
- 電池残量・電池電圧は含めない。追加するなら測定回路とパケット版を設計する。
- iOSの時刻とuptime_msを直接引き算しない。送信→Status受信はiOS内の単調時計で計測する。

## 4. 振動出力

MODE=0、IN2=0を固定し、GPIO3→IN1だけを制御する。HIGHはOUT1=H/OUT2=L、LOWはHi-Z。

| state | 出力案 |
|---|---|
| CLEAR | LOW固定 |
| CAUTION | 150ms HIGH、850ms LOWの繰り返し |
| DANGER | 200ms HIGH、150ms LOWの繰り返し |
| UNAVAILABLE | 危険通知パターンを停止。検知不能へ遷移したときだけ50ms HIGH、100ms LOWを3回の通知案 |

検知不能の通知案は利用者が注意・危険と区別できるかを確認して確定する。起動直後は振動しない。同じUNAVAILABLEの更新・再検出ごとに再生しない。故障や電池切れなら振動通知自体も出せないため、アプリの状態表示と併用する。

## 5. 共通バイト例

`protocol_vectors.json`に正常4例、不正長、不正version、不正state、不正TTL、予約ビット、不正reserved、重複・古いseqの例を収録。

例：DANGER、sequence=1、TTL=1000ms、距離1500mm、flags=0

```text
01 02 01 00 E8 03 DC 05 00 00
```

この例がSwift/C++双方で同じ値に復号されることを、実機結合前に確認する。JSONファイルは通信形式の照合用であり、ファームウェアやiOSの実装テストが合格済みという意味ではない。
