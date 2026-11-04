# 白杖振動デバイス：全体接続回路図

作成日：2026-10-16。最新購入候補に基づくモジュール間接続案。実機では未検証。
白杖は110cm、黒いグリップ。iPhoneは首から下げ、背面カメラを進行方向へ向ける。

## 接続表

| 接続元 | 接続先 |
|---|---|
| 単3アルカリ2本直列の＋ | 電池ボックスのSW1 |
| SW1の出力（VBAT） | AE-TPS63802 CN1-1 VIN、およびAE-DRV8835-P CN2 VM |
| 電池の－ | 全基板のGND |
| AE-TPS63802 CN1-3 VOUT（5.00Vに設定） | 1S4のA（アノード・帯なし側） |
| 1S4のK（カソード・帯側） | XIAOの5V端子 |
| XIAOの3V3 | AE-DRV8835-P CN1 VCC |
| XIAO D1（GPIO3） | AE-DRV8835-P CN1 IN1 |
| AE-DRV8835-P CN1 IN2 | GND |
| AE-DRV8835-P CN1 MODE | GND（IN/INモード） |
| AE-DRV8835-P CN3 OUT1 | LBV10B-009の＋ |
| AE-DRV8835-P CN3 OUT2 | LBV10B-009の－ |

GNDは電池－、電源モジュールCN1-2、XIAO GND、ドライバーCN1/CN2 GNDを全て共通にする。
モジュール内の実装済み回路・コンデンサーは図では省略。
図の箱は接続関係を示すもので、実物の端子順や向きを示さない。端子位置は各マニュアルと基板印字で確認する。

## 設定と動作

- AE-TPS63802：VR1を必ず実装し、XIAO未接続でVOUTを5.00Vに調整する。EN(CN1-4)は基板内でVINへプルアップ済みなので未接続。CP1(PG)も未接続。JP1は短絡してパワーセーブモードとする案。負荷過渡時の電圧を実機確認する。
- AE-DRV8835-P：MODEをGNDにしてIN/INモード。J1ジャンパーで設定する場合もLOW側。VCC側へ短絡する設定と併用しない。
- IN2は常にLOW。IN1 HIGHでOUT1=H/OUT2=Lとなり振動、IN1 LOWで両出力Hi-Zとなり停止。
- LBV10B-009は駆動回路内蔵のブラシレスモーターで極性がある。逆転・ブレーキ設定は使わない。初回は秒単位のON/OFFで確認し、高周波PWMは採用しない。
- IN1/IN2/MODEにはドライバーIC内のプルダウンがある。起動直後のソフトウェアでもD1出力をLOWへ初期化する。
- 電池はモーターへ公称3Vを供給する。新品時の電圧上振れ、電圧低下時の起動・振動・BLE切断を実機確認する。昇圧回路の動作下限とモーターの実用下限は異なる。
- 1S4は昇圧回路側をA、XIAO側をK（帯側）にする。USBから外部電源系への逆流を防ぐ経路。USB接続中はSW1を切ってもXIAOは動作する。電池を充電する回路ではない。
- 電池保持部・回路基板が既存グリップに収まることは未確認。収納設計は白杖の実測後に行う。

## 確認手順

1. 無通電でGND共通、電源極性、電源とGND間の短絡がないことを確認。
2. U1のVR1実装と出力5.00Vを無負荷で確認。
3. 電源OFFでXIAOを接続。起動と3V3出力を確認。
4. ドライバーを接続し、IN1 LOWで停止、HIGHで正しい極性の振動が得られるか短時間確認。
5. BLE接続・切断、繰り返し振動時の電源電圧と平均電流を測定。

## 一次資料

- AE-DRV8835-Pマニュアル：https://akizukidenshi.com/goodsaffix/AE-DRV8835-P_20210526.pdf
- AE-TPS63802マニュアル：https://akizukidenshi.com/goodsaffix/AE-TPS63802.pdf
- XIAO ESP32C3公式ガイド：https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/
- LBV10B-009商品仕様：https://akizukidenshi.com/catalog/g/g106787/
