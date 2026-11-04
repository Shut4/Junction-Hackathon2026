# 白杖振動デバイス｜チーム実装ガイド

更新：<date start="2026-10-17" /> ／ 実装前の共有仕様 v0.1 ／ Mac 2人＋Windows 2人

<callout color="blue_bg">
<b>iPhoneが胸・頭の高さの障害物を検知し、BLEで白杖へ通知して、黒いグリップのモーターを振動させる</b>

白杖は全長110cm。スマホは首から掛け、画面は身体側、背面カメラは進行方向。
</callout>

<callout color="yellow_bg">
<b>既存の検知コードあり／BLE・FW・電池回路は追加作業／外部振動システムは実機検証前</b>

このページの通信値・振動パターンは提案。まず実装前段階として、「障害物→振動→解除」を完成し、採寸後にグリップ一体化へ進む。
</callout>

<table-of-contents />

## 1．全体像

<table fit-page-width="true" header-row="true">
<tr>
<td>
区分
</td>
<td>
内容
</td>
</tr>
<tr>
<td>
ユーザー指定
</td>
<td>
白杖は全長110cm、グリップ付き。iPhoneは首から掛け、背面カメラを進行方向へ向ける。
</td>
</tr>
<tr>
<td>
今回の機能
</td>
<td>
iPhoneで検知 → BLEで危険度送信 → グリップの振動で知らせる
</td>
</tr>
<tr>
<td>
電源案
</td>
<td>
単3アルカリ電池2本で基板と振動用モーターを駆動。XIAO用に昇降圧回路を追加
</td>
</tr>
<tr>
<td>
最終的に目指す機構
</td>
<td>
電池・回路・モーターが黒いグリップ周辺にまとまる構成。既存グリップ内へ収まる機構が理想。電源ボタンのみ白杖の外側に露出させる形。
</td>
</tr>
<tr>
<td>
最初の完成形(MVP)
</td>
<td>
実装前段階として、実際のiOSアプリでの障害物検知からモーター振動、解除まで一通り動作する
</td>
</tr>
<tr>
<td>
今回追加しない範囲
</td>
<td>
白杖側の距離センサー・カメラ、クラウド、独立AI検知、方向別の複数モーター、スマホロック中の継続検知
</td>
</tr>
<tr>
<td>
検証状態
</td>
<td>
新しい外部振動システムは未実機検証。既存コード・過去資料の存在と、今回の結合試験テスト合格を区別する
</td>
</tr>
</table>

```txt
首掛けiPhone（画面は身体側、背面カメラは前方）
  │ AVFoundation：深度を取得 / Core Motion：重力・傾き
  ▼
既存のHeadLevelGeometry：進路上の胸・頭の高さの障害物を判定
  ▼
追加する状態生成処理：注意・危険・検出なし・検知不能を整理
  │ Core Bluetooth / BLE GATT
  ▼
XIAO ESP32C3：受信・期限確認・振動パターン生成
  │ D1（GPIO3）をHIGH/LOW
  ▼
DRV8835：モーターへの電源をON/OFF
  ▼
白杖グリップカバー内のコイン型モーター → 指・手に振動
```

スマホと白杖の間は無線通信。首掛けホルダーは背面カメラを塞がず、歩行中の揺れ・反転・下向きを抑える。

## 2．4人の担当と成果物

<table fit-page-width="true" header-row="true">
<tr>
<td>
担当
</td>
<td>
主担当範囲
</td>
<td>
最初に作るもの
</td>
<td>
完了条件
</td>
<td>
接続先
</td>
</tr>
<tr>
<td>
<b>A：Mac①</b>
</td>
<td>
検知・状態生成・アプリ統合
</td>
<td>
深度結果→外部通知状態への変換
</td>
<td>
注意／危険／検出なし／検知不能と時刻を出力。停止・無効姿勢でCLEARにしない
</td>
<td>
Bへ状態を渡す
</td>
</tr>
<tr>
<td>
<b>B：Mac②</b>
</td>
<td>
iOS BLE・接続画面
</td>
<td>
実機から4状態を手動送信する画面
</td>
<td>
XIAO検索・明示選択・接続・Write・Status受信・切断表示
</td>
<td>
AとCをつなぐ
</td>
</tr>
<tr>
<td>
<b>C：Windows①</b>
</td>
<td>
ファームウェア
</td>
<td>
BLE受信とGPIO出力
</td>
<td>
共通UUID／10バイト仕様で受信、パターン出力、期限切れ停止、Status返信
</td>
<td>
Bの送信とDの回路
</td>
</tr>
<tr>
<td>
<b>D：Windows②</b>
</td>
<td>
回路・電源・黒いグリップ・試験
</td>
<td>
回路組立と単独ON/OFF確認
</td>
<td>
電圧・極性・電流測定、収納寸法確認、折りたたみと握りの確認
</td>
<td>
Cへ回路、全員へ測定結果
</td>
</tr>
</table>

Dは回路単独確認用の短いスケッチを作る場合も、Cの本体ファームウェアと別ファイルにする。CがGPIO割り当てを変更する場合は先にB/Dへ共有。

### ファイル担当案（これから追加・変更する候補）

<table fit-page-width="true" header-row="true">
<tr>
<td>
担当
</td>
<td>
主に扱うファイル
</td>
<td>
競合を減らす取り決め
</td>
</tr>
<tr>
<td>
A
</td>
<td>
<code>Core/HeadLevel.swift</code>、新規<code>Core/CaneAlertState.swift</code>、<code>App/Camera.swift</code>、<code>App/AppStore.swift</code>
</td>
<td>
既存ファイルの編集はAが集約
</td>
</tr>
<tr>
<td>
B
</td>
<td>
新規<code>App/CaneBLEManager.swift</code>、新規<code>App/CaneDeviceScreen.swift</code>、共通プロトコルSwiftファイル、<code>App/Info.plist</code>
</td>
<td>
画面の入口追加・AppStoreへの接続はAと共同確認
</td>
</tr>
<tr>
<td>
C
</td>
<td>
新規<code>Firmware/CaneVibration/</code>、共通定数ヘッダー、ファームウェア導入README
</td>
<td>
ボード・ライブラリのバージョンを記録
</td>
</tr>
<tr>
<td>
D
</td>
<td>
新規<code>Hardware/</code>の組立記録・CAD、<code>Docs/</code>の実機試験結果
</td>
<td>
回路図と実配線を照合し、変更はA/B/Cへ連絡
</td>
</tr>
</table>

上記の新規ファイル・ディレクトリは担当範囲の提案で、まだ実装されていない。

<toggle>
担当者・期限の記入欄と作業チケット

<table fit-page-width="true" header-row="true">
<tr>
<td>
担当
</td>
<td>
氏名
</td>
<td>
端末／OS
</td>
<td>
締切
</td>
<td>
成果物の場所
</td>
</tr>
<tr>
<td>
A：Mac① 検知・統合
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
</tr>
<tr>
<td>
B：Mac② iOS BLE
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
</tr>
<tr>
<td>
C：Windows① FW
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
</tr>
<tr>
<td>
D：Windows② 回路・機構
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
<td>
未記入
</td>
</tr>
</table>

<table fit-page-width="true" header-row="true">
<tr>
<td>
ID
</td>
<td>
担当
</td>
<td>
作業
</td>
<td>
依存
</td>
<td>
完了条件
</td>
<td>
状態
</td>
</tr>
<tr>
<td>
A01
</td>
<td>
A
</td>
<td>
対象iPhone・iOS・深度形式の確認
</td>
<td>
実機
</td>
<td>
実深度フレーム取得ログ
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
A02
</td>
<td>
A
</td>
<td>
有効性・鮮度・4状態のモデル作成
</td>
<td>
A01
</td>
<td>
nil・無効姿勢・古いフレームをUNAVAILABLEへ
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
A03
</td>
<td>
A
</td>
<td>
2フレームの継続判定・状態遷移
</td>
<td>
A02
</td>
<td>
再送と新フレームを区別し、状態変換の単体テスト
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
A04
</td>
<td>
A
</td>
<td>
Bの送信層との結合・停止処理
</td>
<td>
B03
</td>
<td>
自動検知・背景・警告OFF・復帰を確認
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
B01
</td>
<td>
B/C
</td>
<td>
UUIDとパケット版を固定
</td>
<td>
仕様レビュー
</td>
<td>
両側で同じJSON定義・バイト例を使用
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
B02
</td>
<td>
B
</td>
<td>
権限・検索・明示選択・接続画面
</td>
<td>
B01
</td>
<td>
Bluetooth OFF・拒否・候補なしを区別
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
B03
</td>
<td>
B
</td>
<td>
Command送信・Status受信
</td>
<td>
C02
</td>
<td>
手動4状態が実基板へ届く
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
B04
</td>
<td>
B
</td>
<td>
最新1件キュー・周期更新・再接続
</td>
<td>
B03
</td>
<td>
古い指示の滞留なし、最初はUNAVAILABLE
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
C01
</td>
<td>
C
</td>
<td>
Arduino環境・USB書き込み・GPIO確認
</td>
<td>
実基板
</td>
<td>
D1(GPIO3)をLOW/HIGH制御
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
C02
</td>
<td>
C
</td>
<td>
GATTサービス・パケット検証・Status
</td>
<td>
B01
</td>
<td>
正常／不正ベクターとseq周回を照合
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
C03
</td>
<td>
C
</td>
<td>
非ブロッキング振動パターン
</td>
<td>
D02/C02
</td>
<td>
同状態更新で振動位相がリセットされない
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
C04
</td>
<td>
C
</td>
<td>
切断・TTL・起動・再接続
</td>
<td>
C03
</td>
<td>
危険振動が期限切れで停止
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
D01
</td>
<td>
D
</td>
<td>
部品・工具調達、現物型番確認
</td>
<td>
購入
</td>
<td>
欠品・代替・リビジョンを記録
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
D02
</td>
<td>
D
</td>
<td>
電源・ドライバー・モーター組立
</td>
<td>
D01
</td>
<td>
5V調整、3V3、極性、単独振動を測定
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
D03
</td>
<td>
D
</td>
<td>
白杖・グリップ・ホルダー採寸
</td>
<td>
現物
</td>
<td>
径・長さ・シャフト占有・接合部寸法の記録
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
D04
</td>
<td>
D
</td>
<td>
黒グリップカバー／電池収納設計
</td>
<td>
D02/D03
</td>
<td>
交換・絶縁・折りたたみ・握りの確認
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
D05
</td>
<td>
C/D
</td>
<td>
電池側電流・電圧・連続使用測定
</td>
<td>
C03/D02
</td>
<td>
条件と測定点、波形／値を記録
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
I01
</td>
<td>
全員
</td>
<td>
手動指示→BLE→振動
</td>
<td>
B03/C03/D02
</td>
<td>
4状態を第三者が再現
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
I02
</td>
<td>
全員
</td>
<td>
実障害物→BLE→振動→解除
</td>
<td>
A04/I01
</td>
<td>
検知と実振動を同じ時間軸で確認
</td>
<td>
未着手
</td>
</tr>
<tr>
<td>
I03
</td>
<td>
全員
</td>
<td>
デモ前確認・資料整合
</td>
<td>
I02
</td>
<td>
署名・電池・接続・機構・説明資料を確認
</td>
<td>
未着手
</td>
</tr>
</table>
</toggle>

## 3．実装の進め方

<table fit-page-width="true" header-row="true">
<tr>
<td>
段階
</td>
<td>
A
</td>
<td>
B
</td>
<td>
C
</td>
<td>
D
</td>
<td>
全体の出口
</td>
</tr>
<tr>
<td>
M0：準備
</td>
<td>
iPhone深度取得確認
</td>
<td>
UUID・バイト仕様をCと固定
</td>
<td>
USB書き込み確認
</td>
<td>
部品確認・電源調整
</td>
<td>
全員が同じ仕様v0.1を参照
</td>
</tr>
<tr>
<td>
M1：単独動作
</td>
<td>
4状態をログで確認
</td>
<td>
模擬Peripheralなどで送信処理準備
</td>
<td>
PC指示で振動パターン
</td>
<td>
回路単独ON/OFF・電圧確認
</td>
<td>
GPIO→実振動
</td>
</tr>
<tr>
<td>
M2：BLE連携
</td>
<td>
状態出力を整備
</td>
<td>
手動4状態→実XIAO
</td>
<td>
受信とStatus返信
</td>
<td>
実振動の確認
</td>
<td>
iPhoneのボタン→白杖振動
</td>
</tr>
<tr>
<td>
M3：実検知連携
</td>
<td>
検知とBLE入力を接続
</td>
<td>
自動更新・期限・画面
</td>
<td>
切断・TTL・再接続
</td>
<td>
遅延・電源・誤警告測定
</td>
<td>
障害物→振動→解除
</td>
</tr>
<tr>
<td>
M4：機構とデモ
</td>
<td>
首掛け調整
</td>
<td>
デモ表示・無料署名更新
</td>
<td>
起動・再接続を安定化
</td>
<td>
黒グリップ・収納・固定
</td>
<td>
全員が一連の手順を再現
</td>
</tr>
</table>

日程・担当者名・所有iPhone・工具・部品到着日は未指定。最初の打ち合わせで記入する。

<toggle>
使用技術・PC環境・iPhoneへの導入手順

<table fit-page-width="true" header-row="true">
<tr>
<td>
対象
</td>
<td>
技術
</td>
<td>
開発環境
</td>
</tr>
<tr>
<td>
画面・アプリ統合
</td>
<td>
Swift 6 / SwiftUI
</td>
<td>
Mac + Xcode
</td>
</tr>
<tr>
<td>
映像・深度
</td>
<td>
AVFoundation / AVCaptureDepthDataOutput
</td>
<td>
深度出力できるiPhone実機
</td>
</tr>
<tr>
<td>
傾き
</td>
<td>
Core Motion / CMMotionManager
</td>
<td>
iPhone実機
</td>
</tr>
<tr>
<td>
iOS BLE
</td>
<td>
Core Bluetooth / GATT
</td>
<td>
Mac + Xcode + iPhone
</td>
</tr>
<tr>
<td>
白杖側
</td>
<td>
XIAO ESP32C3 / Arduino IDE / C++ / ESP32用BLEライブラリ
</td>
<td>
Windowsでも開発・USB書き込み可
</td>
</tr>
<tr>
<td>
電源
</td>
<td>
TPS63802による5V出力、XIAO内の3.3V生成
</td>
<td>
テスターで調整・確認
</td>
</tr>
<tr>
<td>
モーター
</td>
<td>
DRV8835による固定極性ON/OFF
</td>
<td>
D1(GPIO3)で制御
</td>
</tr>
<tr>
<td>
共同作業
</td>
<td>
Git / GitHub / 仕様ファイル
</td>
<td>
全員。アカウント・証明書は共有しない
</td>
</tr>
</table>

現在のXcodeプロジェクトは最低iOS 26.0、Swift 6.0。Mac側はこのターゲットと接続iPhoneを扱えるXcodeを使う。具体的なXcode版・ESP32ボードパッケージ版は開始時に全員で記録する。

WindowsでiOSの文章・コードを編集することはできるが、今回のAppleフレームワークを含むiOSアプリのビルド・署名・実機インストールはMac側。<code>Core</code>もsimd等を使っているため、Windowsでそのまま全テストが動くとは扱わない。

### Mac側の開始手順

1. Gitで同じ基準のソースを取得し、現在の変更差分を確認する。
2. <code>Config/Local.xcconfig.example</code>を<code>Config/Local.xcconfig</code>へコピーし、自分の<code>JG_TEAM</code>と固有の<code>JG_BUNDLE_ID</code>を設定する。秘密・署名情報はGitへ入れない。
3. <code>JunctionGuide.xcodeproj</code>を開き、Scheme <code>JunctionGuide</code>を選択する。
4. iPhoneの開発モード・信頼・カメラ許可を確認。深度ステータスと実際のデータ取得を確認する。
5. Bは<code>NSBluetoothAlwaysUsageDescription</code>を追加する。Bluetoothの拒否・電源OFFは接続画面で区別する。
6. モデルファイルはGit対象外。既存の全機能を再現する場合は<code>Docs/MODEL.md</code>と<code>Scripts/install_model.sh</code>を確認する。モデル未導入と深度非対応を混同しない。

### 無料Apple Account

Personal Teamで自分のiPhoneへ開発用インストール可能。プロビジョニングは発行から7日で期限切れとなり、再ビルド・再インストールが必要。10 App IDs、3 devices、1台あたり3 appsの制限あり。TestFlight／App Store配布は有料プログラム側。デモ前日に再インストールする。

出典：[Apple Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/)。これは開発運用の条件であり、今回の実機署名成功を保証するものではない。
</toggle>

## 4．回路・黒いグリップ・電池

回路図は下に掲載。配線・電圧調整の説明と併せて確認。

```txt
単3アルカリ2本（公称3V）→ スイッチ → VBAT
  ├─ TPS63802（5V設定）→ 1S4 → XIAO 5V
  └─ DRV8835 VM → OUT1/OUT2 → モーター
XIAO 3V3 → DRV8835 VCC
XIAO D1 / GPIO3 → DRV8835 IN1
DRV8835 IN2・MODE → GND
全てのGND → 電池－
```

- D1という名前は「XIAOのD1端子」と「回路図のダイオードD1」の2か所で使われる。配線時は部品名と端子名を区別。
- TPS63802のVR1を必ず取り付け、XIAO未接続で5.00Vに調整。ENは基板内プルアップにより未接続。JP1短絡で省電力とする案。
- 1S4の帯なし側(A)を電源出力、帯側(K)をXIAO 5Vへ。電圧降下後の基板入力を確認。
- DRV8835-PはIN/INモード。IN2=LOW固定、MODE=LOW、IN1=HIGHでOUT1=H/OUT2=L、IN1=LOWでHi-Z。
- LBV10B-009はブラシレス駆動回路内蔵・極性あり。逆転しない。初期版は秒単位ON/OFF。一般のブラシ付きモーター向けPWMをそのまま適用しない。
- USBデバッグ中は電池スイッチを切ってもXIAOはUSBで動く。電池が充電される回路ではない。
- モーターと無線送受信の負荷で電源が落ちないか測定。低電圧時の状態は未検証。ソフトウェアの電池監視は現状ない。

<image source="notion-file-block://d36b4828-4832-4805-a90b-51e602c74985/162a7797-501b-4556-8365-89491d1deabf?space_id=c394d79e-327d-81d1-b724-000323dd8a22&name=cane-circuit.png" />

<table fit-page-width="true" header-row="true">
<tr>
<td>
部位
</td>
<td>
要求
</td>
<td>
未確認点
</td>
</tr>
<tr>
<td>
白杖
</td>
<td>
全長110cm、黒ゴムグリップ、5段折り
</td>
<td>
実物の径、グリップ取り外し、シャフト・ゴム紐の経路
</td>
</tr>
<tr>
<td>
モーター
</td>
<td>
指に振動が伝わる位置、カバーの内部ポケットへ保持
</td>
<td>
ゴムを挟むことによる減衰・起動時の体感
</td>
</tr>
<tr>
<td>
電池
</td>
<td>
交換可能、逆挿入を抑える、接点を絶縁
</td>
<td>
単3×2本＋ホルダーの収納体積・重量
</td>
</tr>
<tr>
<td>
回路
</td>
<td>
固定・絶縁・配線の引張保護
</td>
<td>
40×25mmのDRV8835-Pを含む収納
</td>
</tr>
<tr>
<td>
折りたたみ
</td>
<td>
接合部や内部ゴム紐を妨げない
</td>
<td>
折りたたみ時の干渉
</td>
</tr>
<tr>
<td>
アンテナ
</td>
<td>
外付けアンテナを保持
</td>
<td>
手・金属シャフトでの電波変化
</td>
</tr>
<tr>
<td>
iPhone
</td>
<td>
首掛け、背面カメラ前方、カメラ開口を確保
</td>
<td>
歩行揺れ、反転、ホルダー寸法、カメラ高さ
</td>
</tr>
</table>

最初は「モーターを既存グリップ外側へ仮固定＋薄い黒カバー」、電子回路・電池は仮ケースで検証。一体化はその後。既存グリップに空洞があることを前提に購入しない。画像生成で示したケース寸法・内部断面は構想であり採寸結果ではない。

<toggle>
電池持ちの考え方と測定項目

現時点では測定値なし。単3×2本なら容量mAhは2倍にならず、直列で電圧が加算される。アルカリ電池の容量は負荷・終止電圧・温度で変わる。

以前の平均電流29.3mAは「50mAで5ms、27mAで45ms」という仮定の時間平均。通信間隔・実際の電流・給電測定点を確定した値ではなく、電池寿命の保証に使わない。

D/Cが測る項目：電池側の平均電流とピーク、電池電圧、昇圧後5V、XIAO入力、3V3、振動時の電圧降下。電池側でモーターを含めて平均電流を測れば、同じ電流をもう一度足さない。基板側で測る場合は電圧と変換効率を含めた電力で換算する。

```txt
平均電池電流 = 測定区間の消費電荷 / 測定時間
基板入力電力 = 基板入力電圧 × その端子で測った電流
電池からの必要電力 ≒ 基板入力電力 / 電源変換効率 + モーター側平均電力
```

8時間動作は評価目標。現状の証拠で達成済みとはしない。
</toggle>

## 5．購入リスト・購入先

金額は2026-10-16に確認した記録値・予算。今回の資料作成では再見積もりしていない。白杖3,600円はユーザー提供画面の値。送料・在庫・注文時の選択を確認する。

<table fit-page-width="true" header-row="true">
<tr>
<td>
品目
</td>
<td>
数量
</td>
<td>
記録値
</td>
<td>
購入先
</td>
</tr>
<tr>
<td>
VISIONU白杖・110cm・黒
</td>
<td>
1
</td>
<td>
3,600円
</td>
<td>
[Amazon](https://www.amazon.co.jp/dp/B07B91QYJ4)
</td>
</tr>
<tr>
<td>
XIAO ESP32C3
</td>
<td>
1
</td>
<td>
1,080円
</td>
<td>
[秋月117454](https://akizukidenshi.com/catalog/g/g117454/)
</td>
</tr>
<tr>
<td>
AE-DRV8835-P
</td>
<td>
1
</td>
<td>
600円
</td>
<td>
[秋月110346](https://akizukidenshi.com/catalog/g/g110346/)
</td>
</tr>
<tr>
<td>
LBV10B-009
</td>
<td>
2（予備1）
</td>
<td>
合計100円
</td>
<td>
[秋月106787](https://akizukidenshi.com/catalog/g/g106787/)
</td>
</tr>
<tr>
<td>
AE-TPS63802
</td>
<td>
1
</td>
<td>
780円
</td>
<td>
[秋月115557](https://akizukidenshi.com/catalog/g/g115557/)
</td>
</tr>
<tr>
<td>
1S4
</td>
<td>
1
</td>
<td>
20円
</td>
<td>
[秋月100127](https://akizukidenshi.com/catalog/g/g100127/)
</td>
</tr>
<tr>
<td>
単3×2本・スイッチ付きBH-321-1AS
</td>
<td>
1
</td>
<td>
70円
</td>
<td>
[秋月100327](https://akizukidenshi.com/catalog/g/g100327/)
</td>
</tr>
<tr>
<td>
単3アルカリ電池
</td>
<td>
1パック
</td>
<td>
予算110円
</td>
<td>
[ダイソー](https://jp.daisonet.com/products/4550480478203)
</td>
</tr>
<tr>
<td>
ピンヘッダー1×40
</td>
<td>
1
</td>
<td>
35円
</td>
<td>
[秋月100167](https://akizukidenshi.com/catalog/g/g100167/)
</td>
</tr>
<tr>
<td>
ユニバーサル基板72×47.5mm
</td>
<td>
1
</td>
<td>
110円
</td>
<td>
[秋月100182](https://akizukidenshi.com/catalog/g/g100182/)
</td>
</tr>
<tr>
<td>
AWG24ワイヤー10色
</td>
<td>
1セット
</td>
<td>
440円
</td>
<td>
[秋月110672](https://akizukidenshi.com/catalog/g/g110672/)
</td>
</tr>
<tr>
<td>
熱収縮チューブ1.5mm
</td>
<td>
1
</td>
<td>
40円
</td>
<td>
[秋月106788](https://akizukidenshi.com/catalog/g/g106788/)
</td>
</tr>
<tr>
<td>
面ファスナー
</td>
<td>
1パック
</td>
<td>
110円
</td>
<td>
[ダイソー（リンクは白。黒は店頭で同等品）](https://jp.daisonet.com/products/4550480325248)
</td>
</tr>
<tr>
<td>
薄手両面テープ
</td>
<td>
1
</td>
<td>
予算110円
</td>
<td>
[ダイソー一覧](https://jp.daisonet.com/collections/stationery0272)
</td>
</tr>
<tr>
<td>
黒ビニールテープ
</td>
<td>
1
</td>
<td>
予算110円
</td>
<td>
[ダイソー一覧](https://jp.daisonet.com/collections/stationery0268)
</td>
</tr>
<tr>
<td>
首掛けスマホホルダー
</td>
<td>
1
</td>
<td>
注文時確認
</td>
<td>
[ダイソー](https://jp.daisonet.com/products/4549131906646)
</td>
</tr>
<tr>
<td>
USB-C通信ケーブル
</td>
<td>
手持ち可
</td>
<td>
注文時確認
</td>
<td>
[ダイソー](https://jp.daisonet.com/products/4550480504599)
</td>
</tr>
</table>

固定金額＋消耗品予算は計7,315円。ホルダー・ケーブル・仮ケース・一体型グリップ製作・送料・工具は別。工具は借用を優先。以前の別体ケースSW-100やFeather、DRV2605L、専用LiPoは最新の必須購入品ではない。

## 6．BLE通信とiOS画面

詳細・バイト例は下の「BLE通信の詳細」に掲載。以下は並行実装のための提案値で、B/Cが実装開始時に同じ版へ固定する。

<table fit-page-width="true" header-row="true">
<tr>
<td>
項目
</td>
<td>
提案
</td>
</tr>
<tr>
<td>
役割
</td>
<td>
iPhone=Central、XIAO=Peripheral
</td>
</tr>
<tr>
<td>
Device name
</td>
<td>
<code>CaneVibe-01</code>。名前だけを機器識別に使わない
</td>
</tr>
<tr>
<td>
発見方法
</td>
<td>
専用Service UUIDをAdvertisingに含め、iPhone側でフィルター
</td>
</tr>
<tr>
<td>
Command
</td>
<td>
10バイト固定 / Write with response
</td>
</tr>
<tr>
<td>
Status
</td>
<td>
10バイト固定 / Read + Notify
</td>
</tr>
<tr>
<td>
状態
</td>
<td>
0=検出なし、1=注意、2=危険、3=検知不能
</td>
</tr>
<tr>
<td>
送信周期
</td>
<td>
接続中250msを目標、状態変更時は早めに送信。Writeを無制限に積まない
</td>
</tr>
<tr>
<td>
フレーム鮮度
</td>
<td>
最終有効深度が600msより古ければ検知不能へ
</td>
</tr>
<tr>
<td>
指示の有効期限
</td>
<td>
受信から1,000ms。期限切れ・切断で危険振動を停止
</td>
</tr>
<tr>
<td>
認証
</td>
<td>
管理されたデモ環境で手動選択。暗号化・Bonding設計は未決定。公開利用対応とは扱わない
</td>
</tr>
<tr>
<td>
電池残量
</td>
<td>
最初の版では表示しない。電圧測定回路は現在の購入リストにない
</td>
</tr>
</table>

検出なしは「有効な範囲内で対象が検出されなかった」という意味で、周囲の安全保証ではない。音声の5秒クールダウンをBLE更新に流用しない。

### 振動パターンの提案

<table fit-page-width="true" header-row="true">
<tr>
<td>
状態
</td>
<td>
提案パターン
</td>
<td>
備考
</td>
</tr>
<tr>
<td>
検出なし
</td>
<td>
OFF
</td>
<td>
新しい有効判定だけで到達
</td>
</tr>
<tr>
<td>
注意
</td>
<td>
ON 150ms → OFF 850msを反復
</td>
<td>
状態が続く間だけ
</td>
</tr>
<tr>
<td>
危険
</td>
<td>
ON 200ms → OFF 150msを反復
</td>
<td>
注意より高い頻度
</td>
</tr>
<tr>
<td>
検知不能／切断／TTL切れ
</td>
<td>
危険振動を停止。必要なら50ms×3回を一度だけ
</td>
<td>
動作不能の通知パターンは利用者確認で最終決定。繰り返し再生しない
</td>
</tr>
</table>

同じ状態の250ms更新で毎回パターンを先頭に戻さない。状態変更時だけスケジュールを切り替え、受信処理を<code>delay()</code>で長時間止めない。1個のモーターで左右方向を伝える仕様は今回設けない。

<toggle>
BLE通信の詳細：UUID・10バイト配置・受信規則・バイト例

<b>状態：今回の共有用に作成した提案。未実装。B（iOS BLE）とC（FW）が同じ版へ固定して使用する。</b>

## 1. GATT

<table fit-page-width="true" header-row="true">
<tr>
<td>
項目
</td>
<td>
値・属性
</td>
</tr>
<tr>
<td>
Local name
</td>
<td>
<code>CaneVibe-01</code>
</td>
</tr>
<tr>
<td>
Service
</td>
<td>
<code>77D6F146-E62C-4ED3-BAAA-6C1526D79D28</code>
</td>
</tr>
<tr>
<td>
Command characteristic
</td>
<td>
<code>BC6B696D-E8D3-4566-9730-EA6B057EE324</code> / Write with response
</td>
</tr>
<tr>
<td>
Status characteristic
</td>
<td>
<code>D9B72442-A4CC-4E98-9352-CED78C12B22F</code> / Read + Notify
</td>
</tr>
<tr>
<td>
Central / Peripheral
</td>
<td>
iPhone / XIAO ESP32C3
</td>
</tr>
<tr>
<td>
数値のバイト順
</td>
<td>
複数バイトの整数は全てLittle Endian
</td>
</tr>
<tr>
<td>
プロトコル版
</td>
<td>
パケット内version=1（文書版v0.1と区別）
</td>
</tr>
</table>

上記128-bit UUIDは今回の試作のために新規生成した値。既存の標準サービスではない。両側で同じ値を使う。

接続時はサービスを探索、StatusのNotifyを有効化、最初はUNAVAILABLEを送る。サービス／属性が一致しなければ自動駆動しない。

## 2. Command：10バイト

<table fit-page-width="true" header-row="true">
<tr>
<td>
Offset
</td>
<td>
長さ
</td>
<td>
名前
</td>
<td>
値
</td>
</tr>
<tr>
<td>
0
</td>
<td>
1
</td>
<td>
version
</td>
<td>
1
</td>
</tr>
<tr>
<td>
1
</td>
<td>
1
</td>
<td>
state
</td>
<td>
0=CLEAR（検出なし）、1=CAUTION、2=DANGER、3=UNAVAILABLE
</td>
</tr>
<tr>
<td>
2
</td>
<td>
2
</td>
<td>
sequence
</td>
<td>
uint16。新しい指示ごとに+1、65535の次は0
</td>
</tr>
<tr>
<td>
4
</td>
<td>
2
</td>
<td>
ttl\_ms
</td>
<td>
uint16。初期版は1000だけを受理
</td>
</tr>
<tr>
<td>
6
</td>
<td>
2
</td>
<td>
distance\_mm
</td>
<td>
0〜65534。未取得は65535（FF FF）。危険度判定はスマホ側
</td>
</tr>
<tr>
<td>
8
</td>
<td>
1
</td>
<td>
flags
</td>
<td>
bit0=床高さが深度から推定された、bit1=手動テスト、bit2〜7=0
</td>
</tr>
<tr>
<td>
9
</td>
<td>
1
</td>
<td>
reserved
</td>
<td>
0
</td>
</tr>
</table>

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
3. 2回目以降は<code>delta=(new-old) mod 65536</code>で、1〜32767だけを新規受理。同一seqは重複、32768〜65535は古いとして駆動状態も期限も更新しない。
4. 受理した時点の単調増加時刻を保存し、受理stateへ移行。同じstateなら振動パターンの位相はリセットせず、期限だけ更新。
5. 更新から1000ms経過、またはBLE切断を検出したら危険振動を停止し、UNAVAILABLEへ。
6. 古いパケットの再到着を新しい指示として扱わない。Write responseはBLE層の応答で、実振動の検出を意味しない。

電源再投入・接続直後のGPIOはLOW。手動テストから自動へ戻す際はUNAVAILABLEを経由する。暗号化／Bondingは未決定なので、公開環境で認証済み制御ができる仕様とは扱わない。

## 3. Status：10バイト

<table fit-page-width="true" header-row="true">
<tr>
<td>
Offset
</td>
<td>
長さ
</td>
<td>
名前
</td>
<td>
値
</td>
</tr>
<tr>
<td>
0
</td>
<td>
1
</td>
<td>
version
</td>
<td>
1
</td>
</tr>
<tr>
<td>
1
</td>
<td>
1
</td>
<td>
applied\_state
</td>
<td>
現在FWが採用している0〜3のstate
</td>
</tr>
<tr>
<td>
2
</td>
<td>
1
</td>
<td>
error\_flags
</td>
<td>
bit0=TTL切れ、bit1=不正パケット検出。以降0
</td>
</tr>
<tr>
<td>
3
</td>
<td>
1
</td>
<td>
gpio\_level
</td>
<td>
現在のGPIO3出力、0=LOW／1=HIGH
</td>
</tr>
<tr>
<td>
4
</td>
<td>
2
</td>
<td>
last\_sequence
</td>
<td>
最後に受理したsequence。未受理時は0＋state=UNAVAILABLE
</td>
</tr>
<tr>
<td>
6
</td>
<td>
4
</td>
<td>
uptime\_ms
</td>
<td>
uint32、FW起動からの単調増加時刻。約49.7日で周回
</td>
</tr>
</table>

- 有効Command受理時、状態変更時、不正パケット受信時、接続中のTTL切れ時にNotifyする。
- <code>last_sequence</code>は受理確認用。<code>gpio_level</code>はGPIO出力の状態であり、モーターの実振動を検出した値ではない。
- 不正パケットフラグは次の有効Command受理でクリア。TTL切れも次の有効Command受理でクリア。
- 電池残量・電池電圧は含めない。追加するなら測定回路とパケット版を設計する。
- iOSの時刻とuptime\_msを直接引き算しない。送信→Status受信はiOS内の単調時計で計測する。

## 4. 振動出力

MODE=0、IN2=0を固定し、GPIO3→IN1だけを制御する。HIGHはOUT1=H/OUT2=L、LOWはHi-Z。

<table fit-page-width="true" header-row="true">
<tr>
<td>
state
</td>
<td>
出力案
</td>
</tr>
<tr>
<td>
CLEAR
</td>
<td>
LOW固定
</td>
</tr>
<tr>
<td>
CAUTION
</td>
<td>
150ms HIGH、850ms LOWの繰り返し
</td>
</tr>
<tr>
<td>
DANGER
</td>
<td>
200ms HIGH、150ms LOWの繰り返し
</td>
</tr>
<tr>
<td>
UNAVAILABLE
</td>
<td>
危険通知パターンを停止。検知不能へ遷移したときだけ50ms HIGH、100ms LOWを3回の通知案
</td>
</tr>
</table>

検知不能の通知案は利用者が注意・危険と区別できるかを確認して確定する。起動直後は振動しない。同じUNAVAILABLEの更新・再検出ごとに再生しない。故障や電池切れなら振動通知自体も出せないため、アプリの状態表示と併用する。

## 5. 共通バイト例

<code>protocol_vectors.json</code>に正常4例、不正長、不正version、不正state、不正TTL、予約ビット、不正reserved、重複・古いseqの例を収録。

例：DANGER、sequence=1、TTL=1000ms、距離1500mm、flags=0

```txt
01 02 01 00 E8 03 DC 05 00 00
```

この例がSwift/C++双方で同じ値に復号されることを、実機結合前に確認する。JSONファイルは通信形式の照合用であり、ファームウェアやiOSの実装テストが合格済みという意味ではない。
</toggle>

<toggle>
iOS接続画面と状態の扱い

Bが追加する最小画面：デバイス検索、候補一覧、接続／切断、接続状態、手動テスト4状態、最終受信Status、エラー表示。

<table fit-page-width="true" header-row="true">
<tr>
<td>
表示・内部状態
</td>
<td>
挙動案
</td>
</tr>
<tr>
<td>
未接続／接続中／接続済み
</td>
<td>
状態を明示。機器名だけで選ばずUUID・接続情報も確認
</td>
</tr>
<tr>
<td>
Bluetooth OFF／権限拒否
</td>
<td>
送信を止めて理由を表示
</td>
</tr>
<tr>
<td>
検知不能
</td>
<td>
取得停止・古いフレーム・無効姿勢を表示。検出なし表示に置き換えない
</td>
</tr>
<tr>
<td>
手動テスト
</td>
<td>
画面上で「模擬」と明示。自動判定と同時送信しない。退出時は検知不能へ
</td>
</tr>
<tr>
<td>
再接続直後
</td>
<td>
古い危険状態を再送しない。最初は検知不能、新しい有効判定後に自動通知再開
</td>
</tr>
<tr>
<td>
背景移行／停止
</td>
<td>
検知不能を送れるなら送信。送れなくても白杖側のTTLで期限切れにする
</td>
</tr>
</table>

初回は前面実行だけ。画面ロック／背景カメラ継続をBLEのバックグラウンド設定だけで解決した扱いにしない。
</toggle>

## 7．結合試験・記録

詳細は下の「全24項目の結合試験」に掲載。各試験は端末・iOS・アプリ版・FW版・電源・設定・期待結果・実結果・ログを記録する。

<table fit-page-width="true" header-row="true">
<tr>
<td>
試験
</td>
<td>
合格の考え方
</td>
</tr>
<tr>
<td>
深度非対応／姿勢不正／カメラ停止
</td>
<td>
CLEARではなく検知不能になる
</td>
</tr>
<tr>
<td>
注意・危険・解除
</td>
<td>
状態に対応するパターンへ遷移。古い指示が残らない
</td>
</tr>
<tr>
<td>
更新停止・アプリ背景・通信切断
</td>
<td>
白杖側で最後の有効指示から1秒以内を目標に危険振動が終了
</td>
</tr>
<tr>
<td>
再接続
</td>
<td>
最初は検知不能、最新判定後に再開
</td>
</tr>
<tr>
<td>
不正長・未対応版・無効TTL
</td>
<td>
受理しない。GPIOは動かさず期限も延長しない
</td>
</tr>
<tr>
<td>
電源ON／OFF・モーター負荷
</td>
<td>
意図しない振動、リセット、異常な電圧降下がない
</td>
</tr>
<tr>
<td>
握り・折りたたみ・首掛け
</td>
<td>
接合部やカメラを塞がず、配線の引張・ケースのずれがない
</td>
</tr>
<tr>
<td>
振動体感
</td>
<td>
地面からの白杖の感触と、通知振動を区別できるか利用者と確認
</td>
</tr>
<tr>
<td>
連続使用
</td>
<td>
電池・iPhoneの発熱、検知欠損、BLE切断を記録
</td>
</tr>
</table>

Status受信は「基板が指示を解釈した」証拠で、実振動を測った証拠ではない。モーターの振動センサーは搭載しないため、体感・動画・測定と区別する。

iPhoneとXIAOは別時計。両者の時刻をそのまま引いて片道遅延を求めない。iPhone側の送信→Status受信は往復相当の指標。障害物提示→実振動は動画等で同じ時間軸に載せる。

<toggle>
全24項目の結合試験（全て未実施）

<table fit-page-width="true" header-row="true">
<tr>
<td>
No.
</td>
<td>
ケース
</td>
<td>
期待結果
</td>
<td>
主担当
</td>
<td>
結果
</td>
</tr>
<tr>
<td>
T01
</td>
<td>
電池OFF・USBなし
</td>
<td>
モーターOFF
</td>
<td>
D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T02
</td>
<td>
電池ON・BLE未接続
</td>
<td>
意図しない危険振動なし
</td>
<td>
C/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T03
</td>
<td>
U1出力・XIAO入力・3V3
</td>
<td>
調整値と基板仕様内、振動負荷で起動維持
</td>
<td>
D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T04
</td>
<td>
iPhone Bluetooth OFF／権限拒否
</td>
<td>
理由表示、接続済みと表示しない
</td>
<td>
B
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T05
</td>
<td>
サービスUUID不一致
</td>
<td>
自動制御しない
</td>
<td>
B/C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T06
</td>
<td>
手動CAUTION/DANGER/CLEAR
</td>
<td>
対応振動・停止、Statusのseq一致
</td>
<td>
B/C/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T07
</td>
<td>
250msの同じ状態更新
</td>
<td>
同じ振動パターンが途切れず進む
</td>
<td>
C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T08
</td>
<td>
不正長・版・state・TTL・予約値
</td>
<td>
状態と期限を更新せず、エラー通知
</td>
<td>
B/C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T09
</td>
<td>
重複seq・古いseq・65535→0
</td>
<td>
重複／古い値は期限延長なし、周回後は新規受理
</td>
<td>
C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T10
</td>
<td>
指示更新停止
</td>
<td>
最後の有効指示から1000ms経過で危険パターン停止。実測値記録
</td>
<td>
C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T11
</td>
<td>
BLE切断・距離離隔
</td>
<td>
検知不能。再接続だけで古い危険状態を再開しない
</td>
<td>
B/C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T12
</td>
<td>
深度非対応・起動失敗・無効姿勢
</td>
<td>
UNAVAILABLE。CLEARを送らない
</td>
<td>
A
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T13
</td>
<td>
深度が600ms以上途絶える
</td>
<td>
UNAVAILABLEへ遷移し、TTLが新しい危険として延長されない
</td>
<td>
A/B
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T14
</td>
<td>
アプリ背景／画面ロック／カメラ停止
</td>
<td>
検知停止を明示。送信できなくても白杖側で期限切れ
</td>
<td>
A/B/C
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T15
</td>
<td>
前面復帰
</td>
<td>
新しい有効深度までUNAVAILABLE
</td>
<td>
A/B
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T16
</td>
<td>
実障害物2〜2.5m／2m以内
</td>
<td>
閾値に対応。測距誤差と実際の保存設定を記録
</td>
<td>
A/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T17
</td>
<td>
地面・高さ対象外・側方対象外
</td>
<td>
対象外を頭部障害物として通知しないか確認
</td>
<td>
A
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T18
</td>
<td>
暗所・ガラス・細い枝
</td>
<td>
見逃し・欠損を記録。非検出を安全保証にしない
</td>
<td>
A/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T19
</td>
<td>
首掛けで歩行・反転・揺れ
</td>
<td>
カメラ向きと取得状態、誤警告回数を記録
</td>
<td>
A/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T20
</td>
<td>
配線引張・握り・5段折りたたみ
</td>
<td>
接合部・内部紐・手の操作を妨げず、部品がずれない
</td>
<td>
D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T21
</td>
<td>
電池低下・連続使用
</td>
<td>
電池側消費、振動起動、BLE再起動／切断を記録
</td>
<td>
C/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T22
</td>
<td>
USB接続中にSW1 OFF
</td>
<td>
XIAOはUSBで動くことを確認。電池への逆流経路を確認
</td>
<td>
D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T23
</td>
<td>
受信Statusだけ成功・モーター外れ
</td>
<td>
Statusは物理振動の証明ではないことをログと実物で区別
</td>
<td>
B/C/D
</td>
<td>
未実施
</td>
</tr>
<tr>
<td>
T24
</td>
<td>
デモ前日・当日
</td>
<td>
Personal Team署名の有効性、電池、再接続、最新コードを確認
</td>
<td>
全員
</td>
<td>
未実施
</td>
</tr>
</table>
</toggle>

<toggle>
試験結果の記録テンプレート

```txt
試験ID：
実施日時／担当者：
iPhone型番／iOS：
アプリcommit／作業差分／設定：
FW commit／Arduino IDE／ESP32ボードパッケージ／BLEライブラリ版：
回路基板リビジョン／モーター型番：
電池の銘柄・種類・使用履歴／開始電圧：
モーターの通知パターン／頻度：
期待結果：
実際の結果：
ログ・動画・測定値の保存先：
判定：未実施／合格／不合格／条件付き
課題・次の作業：
```
</toggle>

## 8．未決定事項と既存コード

<table fit-page-width="true" header-row="true">
<tr>
<td>
項目
</td>
<td>
担当
</td>
<td>
現状
</td>
</tr>
<tr>
<td>
検証用iPhoneの型番・iOS・深度出力
</td>
<td>
A
</td>
<td>
未確定
</td>
</tr>
<tr>
<td>
4人の担当者名と締切
</td>
<td>
全員
</td>
<td>
未指定
</td>
</tr>
<tr>
<td>
UUID・10バイト通信案の採用版
</td>
<td>
B/C
</td>
<td>
本資料の提案。未実装
</td>
</tr>
<tr>
<td>
検知不能の振動パターン
</td>
<td>
全員・利用者
</td>
<td>
提案値。危険通知との区別を確認
</td>
</tr>
<tr>
<td>
深度の有効性基準・600ms閾値
</td>
<td>
A
</td>
<td>
追加設計が必要
</td>
</tr>
<tr>
<td>
BLE接続間隔・ライブラリ版・再接続
</td>
<td>
B/C
</td>
<td>
実機で調整
</td>
</tr>
<tr>
<td>
電池低下時の実用終止電圧・動作時間
</td>
<td>
C/D
</td>
<td>
未測定
</td>
</tr>
<tr>
<td>
黒グリップの収納寸法・製造方法
</td>
<td>
D
</td>
<td>
白杖到着後に実測
</td>
</tr>
<tr>
<td>
購入済み部品・工具・予算
</td>
<td>
D
</td>
<td>
購入済みの報告なし
</td>
</tr>
</table>

<toggle>
現コードの状況・検知パラメーター・直す境界

2026-10-17に現在の作業ツリーを確認。アプリ本体はSwift 35ファイル・3,885行（空行・コメント込み）、テスト2ファイル・888行。今回、アプリのソース変更やビルド・テストは行っていない。

<table fit-page-width="true" header-row="true">
<tr>
<td>
機能
</td>
<td>
現状
</td>
<td>
根拠
</td>
</tr>
<tr>
<td>
カメラ映像・深度取得
</td>
<td>
コードあり。対応形式がなければ深度非対応を表示
</td>
<td>
<code>App/Camera.swift</code>
</td>
</tr>
<tr>
<td>
重力方向から高さ・進路を計算
</td>
<td>
コードあり
</td>
<td>
<code>Core/HeadLevel.swift</code>
</td>
</tr>
<tr>
<td>
胸・頭の高さの障害物判定
</td>
<td>
コードあり。深度点の幾何判定
</td>
<td>
<code>HeadLevelGeometry.evaluate</code>
</td>
</tr>
<tr>
<td>
音声・iPhone本体の振動
</td>
<td>
コードあり
</td>
<td>
<code>App/AppStore.swift</code> / <code>App/Services.swift</code>
</td>
</tr>
<tr>
<td>
画像の物体認識
</td>
<td>
Vision/Core MLの既存コードあり。胸・頭の高さ判定の必須処理とは別
</td>
<td>
<code>App/Camera.swift</code> / <code>Docs/MODEL.md</code>
</td>
</tr>
<tr>
<td>
地図・経路案内・通行不可報告
</td>
<td>
既存機能。今回の白杖連携の中心対象外
</td>
<td>
README / Coreの経路処理
</td>
</tr>
<tr>
<td>
BLE接続・送受信
</td>
<td>
<b>未実装</b>。CoreBluetooth実装を検出しなかった
</td>
<td>
App / Coreを検索
</td>
</tr>
<tr>
<td>
Bluetooth利用目的文
</td>
<td>
<b>未追加</b>
</td>
<td>
<code>App/Info.plist</code>に<code>NSBluetoothAlwaysUsageDescription</code>なし
</td>
</tr>
<tr>
<td>
白杖のファームウェア
</td>
<td>
<b>未作成</b>
</td>
<td>
今回のリポジトリに対象実装なし
</td>
</tr>
<tr>
<td>
外部回路・一体型グリップ
</td>
<td>
接続図・仕様書・構想のみ
</td>
<td>
<code>output/hardware</code>
</td>
</tr>
</table>

### 胸・頭の高さ検知の初期値

<table fit-page-width="true" header-row="true">
<tr>
<td>
項目
</td>
<td>
現コードの初期値
</td>
<td>
意味
</td>
</tr>
<tr>
<td>
前方距離
</td>
<td>
0.3〜2.5m
</td>
<td>
この範囲の深度点を対象
</td>
</tr>
<tr>
<td>
進路幅
</td>
<td>
中心から左右各0.45m
</td>
<td>
合計0.9m
</td>
</tr>
<tr>
<td>
床からの高さ
</td>
<td>
1.0〜2.0m
</td>
<td>
利用者の身長に自動追従する実装ではない
</td>
</tr>
<tr>
<td>
危険
</td>
<td>
2.0m以内
</td>
<td>
<code>.danger</code>
</td>
</tr>
<tr>
<td>
注意
</td>
<td>
2.0m超〜2.5m
</td>
<td>
<code>.caution</code>
</td>
</tr>
<tr>
<td>
深度点数
</td>
<td>
12点以上
</td>
<td>
高さ・進路条件を満たす点が必要
</td>
</tr>
<tr>
<td>
深度処理間隔
</td>
<td>
少なくとも0.2秒
</td>
<td>
最大約5回/秒。実際の取得頻度は端末依存
</td>
</tr>
<tr>
<td>
カメラ高さの初期値
</td>
<td>
1.3m
</td>
<td>
床が推定できない場合に使用。設定値は保存される
</td>
</tr>
<tr>
<td>
音声警告の継続判定
</td>
<td>
2フレーム
</td>
<td>
即時の単発ノイズを抑える
</td>
</tr>
<tr>
<td>
音声の再通知間隔
</td>
<td>
5秒
</td>
<td>
外部振動の更新周期には流用しない
</td>
</tr>
<tr>
<td>
近接ブザー
</td>
<td>
1m以内
</td>
<td>
現コードの音通知。外部モーターとは別
</td>
</tr>
</table>

これらは定数の初期値であり、端末の保存済み設定と一致するとは限らない。首掛け位置と利用者に合わせて確認する。1mより近くても新しい第3の振動段階は今回追加せず、まず既存の注意／危険で統一する提案。

### 今回の追加で特に直す境界

- <code>HeadLevelAnnouncer</code>は音声の再通知制御。ここからだけBLE送信すると5秒間隔などに制限されるため、深度結果から独立して外部通知状態を生成する。
- <code>hit == nil</code>だけでは検知不能と検出なしを区別できない。無効姿勢・深度欠損・停止・最新フレーム時刻を持つ状態へ拡張する。
- <code>HeadLevelGeometry.axes(...) == nil</code>時は現在<code>hit=nil</code>の結果を返す。この結果をCLEARへ変換しない。
- カメラ側はnil結果を<code>onDepth</code>へ転送しない経路がある。最後の有効フレーム時刻だけでなく、明示的な取得エラーも外部状態へ伝える。
- <code>App/JunctionGuideApp.swift</code>は背景移行で<code>store.pause()</code>を呼び、カメラ等を停止する。前面復帰後は新しい深度を得るまで検知不能とする。
</toggle>

<toggle>
Gitの分担・既存差分・モデルの扱い

- A/B/C/Dの分担ごとに作業ブランチを用意する案：<code>feature/ios-hazard-state</code>、<code>feature/ios-cane-ble</code>、<code>feature/cane-firmware</code>、<code>feature/cane-hardware-docs</code>。
- 現在すでにAppStore・CameraGuidance・HomeScreen・翻訳・Detection・Walkableに未コミット変更がある。作業開始時に所有者を確認し、上書き・リセットしない。
- 共通プロトコルのUUID・状態値・バイト順・タイムアウトを変えたら、B/C両方と仕様を同時更新する。<code>protocol_vectors.json</code>を共通照合データにする（リポジトリ内資料）。
- Apple Account、署名情報、端末UDID、ローカルパス、秘密鍵は共有コードへ入れない。
- モデルはGit対象外。既存のモデル利用条件の未確認点は<code>Docs/MODEL.md</code>を保持し、公開・再配布を自動的に許可された扱いにしない。
- 初回チェックはMacで<code>swift test</code>と適切なiPhoneへのビルド。ファームウェアは固定したボード設定でコンパイルし、実基板でGPIOとBLEを確認。
- テストファイルの存在と今回の実行結果を区別する。本書作成ではテストを実行していない。
</toggle>

## 9．仕様書・公式資料（31件）

2026年10月16日に収集した原本のリンク。購入基板のリビジョン・モーターの実物型番を照合する。FD216はモーター内部ICの資料であり、モーター本体の完全な仕様書ではない。Energizer電池の資料は参考で、ダイソー電池そのものの放電曲線ではない。白杖グリップ内部寸法は未確認。

<toggle>
BLE基板・SoC・開発ガイド（11件）

- [XIAO ESP32C3 製品データシート](https://files.seeedstudio.com/Bazaar/product_pdf/113991054.pdf)：採用基板
- [XIAO ESP32C3 回路図 v1.3](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/XIAO_ESP32C3_v1.3_SCH_260116.pdf)：購入基板のリビジョン一致を確認する
- [XIAO ESP32C3 旧版回路図](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/Seeeduino-XIAO-ESP32C3-SCH.pdf)：比較用。v1.3と混在させない
- [XIAO ESP32C3 公式ガイド](https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/)：仕様・ピン配置・外部電源・Arduino導入
- [XIAO ESP32C3 消費電力レポート](https://files.seeedstudio.com/wiki/Seeed-Studio-XIAO-ESP32/Low_Power_Consumption.pdf)：公開試験条件での参考値。今回の実装の平均電流ではない
- [XIAO ESP32C3 ピン配列表](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/XIAO-ESP32C3-pinout_sheet.xlsx)：公式配布の原本。編集なし
- [XIAO ESP32C3 外形寸法DXF](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/XIAO-ESP32C3-DXF.zip)：公式配布CAD原本
- [ESP32-C3 ICデータシート](https://www.espressif.com/sites/default/files/documentation/esp32-c3_datasheet_en.pdf)：基板全体ではなく搭載SoCの仕様
- [XIAO ESP32C3 BLE通信公式ガイド](https://wiki.seeedstudio.com/XIAO_ESP32C3_Bluetooth_Usage/)：GATT・BLE受信の実装用
- [TLV757P XIAO搭載レギュレータ仕様](https://www.ti.com/lit/ds/symlink/tlv757p.pdf)：XIAO回路図の搭載型番と照合。別途購入不要
- [ESP32-C3 省電力モード公式ドキュメント](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/sleep_modes.html)：BLE接続維持と自動Light-sleepの条件
</toggle>

<toggle>
モータードライバー（2件）

- [AE-DRV8835-P 基板マニュアル](https://akizukidenshi.com/goodsaffix/AE-DRV8835-P_20210526.pdf)：今回の600円キット。旧小型S基板ではない
- [DRV8835 ICデータシート](https://www.ti.com/lit/ds/symlink/drv8835.pdf)：電気定格・制御真理値表
</toggle>

<toggle>
電源・ダイオード・電池（6件）

- [AE-TPS63802 基板マニュアル](https://akizukidenshi.com/goodsaffix/AE-TPS63802.pdf)：VR1・EN・JP1・入出力端子・組立
- [TPS63802 ICデータシート](https://www.ti.com/lit/ds/symlink/tps63802.pdf)：電気定格・効率・負荷特性
- [1S4 ショットキーダイオード仕様](https://akizukidenshi.com/goodsaffix/1S4.pdf)：極性・順方向電圧・逆電圧
- [BH-321-1AS 電池ボックス寸法図](https://akizukidenshi.com/goodsaffix/BH-321-1AS.pdf)：最新リストのリード線・スイッチ付き型番
- [Energizer E91 単3アルカリ電池仕様](https://data.energizer.com/pdfs/e91.pdf)：参考資料。購入予定ダイソー乾電池の性能保証には使えない
- [ダイソー 単3アルカリ電池4本 商品仕様](https://jp.daisonet.com/products/4550480478203)：購入候補そのものの公開仕様。詳細放電曲線は未入手
</toggle>

<toggle>
振動モーター（3件）

- [LBV10B-009 販売元仕様](https://akizukidenshi.com/catalog/g/g106787/)：モーター本体：定格3V・50mA・直径10mm・極性あり
- [LBV10B-009 端子極性図](https://akizukidenshi.com/goodsaffix/LBV10B-009.png)：モーター本体の接続方向
- [FD216 モーター内蔵IC参考資料](https://akizukidenshi.com/goodsaffix/FD216.pdf)：販売元が参考掲載。モーター本体の完全仕様書ではない
</toggle>

<toggle>
配線・基板・絶縁用品（6件）

- [PH-1xXXSG ピンヘッダー寸法図](https://akizukidenshi.com/goodsaffix/PH-1xXXSG-AD.pdf)：採用品1×40を含むシリーズ寸法図
- [ユニバーサル基板 Cタイプ外形図](https://akizukidenshi.com/goodsaffix/p182.pdf)：基板サイズ確認
- [耐熱ワイヤー IRRAX材料参考仕様](https://akizukidenshi.com/goodsaffix/irraxa.pdf)：販売元の参考資料。AWG24商品の仕様ページも参照
- [耐熱ワイヤー AWG24×10色 商品仕様](https://akizukidenshi.com/catalog/g/g110672/)：採用商品そのものの公開仕様
- [スミチューブC シリーズ仕様](https://www.sei-sfp.co.jp/products/pdf/SUMITUBE-C.pdf)：メーカー公開のスミチューブCカタログ。寸法・収縮・材料仕様
- [スミチューブC 内径1.5mm 商品仕様](https://akizukidenshi.com/catalog/g/g106788/)：選定寸法の確認
</toggle>

<toggle>
首掛け・固定・ケーブル（3件）

- [首掛けスマホホルダー 商品仕様](https://jp.daisonet.com/products/4549131906646)：使用iPhoneの寸法・カメラ開口・向きは現物照合
- [面ファスナー結束バンド 商品仕様](https://jp.daisonet.com/products/4550480325248)：商品ページは白色。黒色採用時は別商品を確認
- [USB-C充電通信ケーブル 商品仕様](https://jp.daisonet.com/products/4550480504599)：書き込み・デバッグ用。手持ちを流用可
</toggle>

[Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth) ／ [無料Apple Accountの条件](https://developer.apple.com/help/account/basics/about-your-developer-account/) ／ [XIAO公式導入ガイド](https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/)

---

このページをチームの参照先とし、担当者・期限・購入状況・実測結果を更新する。仕様案と実装・試験結果を区別して記録する。