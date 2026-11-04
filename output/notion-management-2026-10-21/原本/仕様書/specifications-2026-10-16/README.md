# 白杖振動デバイス 仕様書・技術資料集

取得日：2026-10-16 JST。取得資料31件（PDF 18件、HTML 10件、PNG/XLSX/DXF ZIP 各1件）＋既存接続図3ファイル。

## 対象部品と資料の充足状況

| 対象 | 資料 | 確認範囲・不足 |
|---|---|---|
| XIAO ESP32C3 | 製品PDF・回路図2版・ピン表・寸法CAD・低消費電力レポート・公式ガイド | 収録済み。購入基板のリビジョン照合が必要 |
| ESP32-C3 / TLV757P | SoC / 基板搭載レギュレータのメーカーPDF | 収録済み。部品単体を別途購入する必要はない |
| AE-DRV8835-P / DRV8835 | 秋月基板マニュアル＋TI ICデータシート | 収録済み。P基板が対象。S基板の端子配置を流用しない |
| AE-TPS63802 / TPS63802 | 秋月基板マニュアル＋TI ICデータシート | 収録済み。VR1実装・無負荷で5.00V調整 |
| 1S4 | 販売元配布のデータシート | 収録済み |
| BH-321-1AS | 電池ボックスの寸法図 | 収録済み。既存グリップ内部への収納可否は未確認 |
| LBV10B-009 | 販売元仕様HTML＋極性PNG＋FD216参考PDF | 本体の完全なメーカー仕様書は公開資料から未入手。FD216は内蔵IC参考資料であり本体仕様書ではない |
| 単3アルカリ乾電池 | ダイソーの商品仕様HTML＋Energizer E91参考PDF | 採用品の放電曲線・容量保証は未入手。E91の値をダイソー品へ転用しない |
| ピンヘッダー / ユニバーサル基板 | 寸法図PDF | 収録済み。キット内付属品は基板マニュアルの部品表を参照 |
| AWG24配線 / スミチューブC | 商品仕様HTML＋メーカー材料・シリーズPDF | 収録済み。材料参考と商品個別仕様を区別 |
| 110cm白杖・黒グリップ | 利用者提供の商品画面に記載された仕様と購入リンク | 完全な構造図・グリップ径・内部構造は未入手。個人情報を含む元スクリーンショットは同梱しない |
| 首掛けホルダー / 面ファスナー / USBケーブル | 販売元の商品仕様HTML | 収録済み。ホルダーは使用iPhoneと実物で照合。掲載バンドは白色なので黒色採用時は別商品確認 |
| 黒い自作グリップ / 追加カバー | 現物寸法に合わせて設計する部品 | 未設計。既製品仕様書なし。収納を保証する資料はない |
| 両面テープ / 黒ビニールテープ | 汎用消耗品、品番未確定 | 商品一覧リンクを収録。採用品確定後に個別仕様を取得 |
| iPhone | 機種未指定 | 機種別仕様書は未収録。深度出力対応カメラを実機確認 |

## 資料の読み方・設計上の留意点

- 最初は `00_project` の接続図と接続表、DRV8835-P基板マニュアル、TPS63802基板マニュアル、XIAO公式ガイドを読む。
- これは資料集であり、回路・機構の実機検証完了を示すものではない。
- 白杖は全長110cm・黒いグリップ。iPhoneは首掛けで背面カメラを進行方向へ向ける構想。
- モーター内蔵ICの資料とモーター本体の仕様、IC単体と完成基板、別ブランド電池を混同しない。
- XIAOの回路図は新版と旧版を分けて保存。実物のリビジョンに一致するものを使用する。
- 電源回路のスイッチング電流と、完成モジュールから常時取り出せる電流は異なる。入力電圧・温度・効率条件を確認する。
- モーターは内蔵駆動回路のあるブラシレス型。極性固定で使い、逆転・ブレーキ・高周波PWMを前提としない。
- 消費電流約29mAは以前の条件付き計算例であり測定値ではない。低消費電力レポートと実装の動作条件を照合する。
- アルカリ電池は充電しない。XIAOのBAT端子ではなく、外付け電源モジュール経由の回路案。
- HTMLは公開ページから抽出した静的テキスト保存。写真・図・動画・動的要素は出典リンクで確認する。原本PDF、XLSX、DXF ZIPは変更していない。
- ダウンロードした公式DXF ZIPは展開せず収録。開発メンバーが必要時に展開する。
- 取得日は2026-10-16 JST。ファイルの取得URL、サイズ、PDFページ数、SHA-256をmanifest.jsonに収録。元資料の権利は各権利者に帰属する。

## 購入候補・未確定資料の出典

- 白杖（ASIN B07B91QYJ4）：https://www.amazon.co.jp/dp/B07B91QYJ4
- 両面テープ商品一覧：https://jp.daisonet.com/collections/stationery0272
- 黒ビニールテープ商品一覧：https://jp.daisonet.com/collections/stationery0268
- iOS Core Bluetooth公式：https://developer.apple.com/documentation/corebluetooth
- iOS 深度出力API公式：https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput
- iOS Core Motion公式：https://developer.apple.com/documentation/coremotion

## BLE基板・搭載SoC・ソフトウェア

| 資料 | 保存ファイル | 出典 | 備考 |
|---|---|---|---|
| XIAO ESP32C3 製品データシート | [01_XIAO_ESP32C3_product.pdf](01_ble/01_XIAO_ESP32C3_product.pdf) | [公開元](https://files.seeedstudio.com/Bazaar/product_pdf/113991054.pdf) | 採用基板 |
| XIAO ESP32C3 回路図 v1.3 | [02_XIAO_ESP32C3_schematic_v1.3.pdf](01_ble/02_XIAO_ESP32C3_schematic_v1.3.pdf) | [公開元](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/XIAO_ESP32C3_v1.3_SCH_260116.pdf) | 購入基板のリビジョン一致を確認する |
| XIAO ESP32C3 旧版回路図 | [03_XIAO_ESP32C3_schematic_legacy.pdf](01_ble/03_XIAO_ESP32C3_schematic_legacy.pdf) | [公開元](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/Seeeduino-XIAO-ESP32C3-SCH.pdf) | 比較用。v1.3と混在させない |
| XIAO ESP32C3 公式ガイド | [04_XIAO_ESP32C3_getting_started.html](01_ble/04_XIAO_ESP32C3_getting_started.html) | [公開元](https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/) | 仕様・ピン配置・外部電源・Arduino導入 |
| XIAO ESP32C3 消費電力レポート | [05_XIAO_ESP32C3_low_power.pdf](01_ble/05_XIAO_ESP32C3_low_power.pdf) | [公開元](https://files.seeedstudio.com/wiki/Seeed-Studio-XIAO-ESP32/Low_Power_Consumption.pdf) | 公開試験条件での参考値。今回の実装の平均電流ではない |
| XIAO ESP32C3 ピン配列表 | [06_XIAO_pinout.xlsx](01_ble/06_XIAO_pinout.xlsx) | [公開元](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/XIAO-ESP32C3-pinout_sheet.xlsx) | 公式配布の原本。編集なし |
| XIAO ESP32C3 外形寸法DXF | [07_XIAO_dimensions_DXF.zip](01_ble/07_XIAO_dimensions_DXF.zip) | [公開元](https://files.seeedstudio.com/wiki/XIAO_WiFi/Resources/XIAO-ESP32C3-DXF.zip) | 公式配布CAD原本 |
| ESP32-C3 ICデータシート | [08_ESP32_C3_datasheet.pdf](01_ble/08_ESP32_C3_datasheet.pdf) | [公開元](https://www.espressif.com/sites/default/files/documentation/esp32-c3_datasheet_en.pdf) | 基板全体ではなく搭載SoCの仕様 |
| XIAO ESP32C3 BLE通信公式ガイド | [09_XIAO_BLE_guide.html](01_ble/09_XIAO_BLE_guide.html) | [公開元](https://wiki.seeedstudio.com/XIAO_ESP32C3_Bluetooth_Usage/) | GATT・BLE受信の実装用 |
| TLV757P XIAO搭載レギュレータ仕様 | [11_TLV757P_regulator_datasheet.pdf](01_ble/11_TLV757P_regulator_datasheet.pdf) | [公開元](https://www.ti.com/lit/ds/symlink/tlv757p.pdf) | XIAO回路図の搭載型番と照合。別途購入不要 |
| ESP32-C3 省電力モード公式ドキュメント | [10_ESP32_C3_sleep_modes.html](01_ble/10_ESP32_C3_sleep_modes.html) | [公開元](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/sleep_modes.html) | BLE接続維持と自動Light-sleepの条件 |

## モータードライバー基板・IC

| 資料 | 保存ファイル | 出典 | 備考 |
|---|---|---|---|
| AE-DRV8835-P 基板マニュアル | [01_AE_DRV8835_P_manual.pdf](02_motor_driver/01_AE_DRV8835_P_manual.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/AE-DRV8835-P_20210526.pdf) | 今回の600円キット。旧小型S基板ではない |
| DRV8835 ICデータシート | [02_DRV8835_datasheet.pdf](02_motor_driver/02_DRV8835_datasheet.pdf) | [公開元](https://www.ti.com/lit/ds/symlink/drv8835.pdf) | 電気定格・制御真理値表 |

## 電源・ダイオード・電池

| 資料 | 保存ファイル | 出典 | 備考 |
|---|---|---|---|
| AE-TPS63802 基板マニュアル | [01_AE_TPS63802_manual.pdf](03_power/01_AE_TPS63802_manual.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/AE-TPS63802.pdf) | VR1・EN・JP1・入出力端子・組立 |
| TPS63802 ICデータシート | [02_TPS63802_datasheet.pdf](03_power/02_TPS63802_datasheet.pdf) | [公開元](https://www.ti.com/lit/ds/symlink/tps63802.pdf) | 電気定格・効率・負荷特性 |
| 1S4 ショットキーダイオード仕様 | [03_1S4_datasheet.pdf](03_power/03_1S4_datasheet.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/1S4.pdf) | 極性・順方向電圧・逆電圧 |
| BH-321-1AS 電池ボックス寸法図 | [04_BH_321_1AS_drawing.pdf](03_power/04_BH_321_1AS_drawing.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/BH-321-1AS.pdf) | 最新リストのリード線・スイッチ付き型番 |
| Energizer E91 単3アルカリ電池仕様 | [05_Energizer_AA_alkaline_reference.pdf](03_power/05_Energizer_AA_alkaline_reference.pdf) | [公開元](https://data.energizer.com/pdfs/e91.pdf) | 参考資料。購入予定ダイソー乾電池の性能保証には使えない |
| ダイソー 単3アルカリ電池4本 商品仕様 | [06_DAISO_AA_battery_product.html](03_power/06_DAISO_AA_battery_product.html) | [公開元](https://jp.daisonet.com/products/4550480478203) | 購入候補そのものの公開仕様。詳細放電曲線は未入手 |

## 振動モーター・極性・内蔵IC参考

| 資料 | 保存ファイル | 出典 | 備考 |
|---|---|---|---|
| LBV10B-009 販売元仕様 | [01_LBV10B_009_product.html](04_motor/01_LBV10B_009_product.html) | [公開元](https://akizukidenshi.com/catalog/g/g106787/) | モーター本体：定格3V・50mA・直径10mm・極性あり |
| LBV10B-009 端子極性図 | [02_LBV10B_009_polarity.png](04_motor/02_LBV10B_009_polarity.png) | [公開元](https://akizukidenshi.com/goodsaffix/LBV10B-009.png) | モーター本体の接続方向 |
| FD216 モーター内蔵IC参考資料 | [03_FD216_internal_IC_reference.pdf](04_motor/03_FD216_internal_IC_reference.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/FD216.pdf) | 販売元が参考掲載。モーター本体の完全仕様書ではない |

## 配線・基板・絶縁部材

| 資料 | 保存ファイル | 出典 | 備考 |
|---|---|---|---|
| PH-1xXXSG ピンヘッダー寸法図 | [01_PH_1x40SG_drawing.pdf](05_wiring/01_PH_1x40SG_drawing.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/PH-1xXXSG-AD.pdf) | 採用品1×40を含むシリーズ寸法図 |
| ユニバーサル基板 Cタイプ外形図 | [02_AE3_perfboard_drawing.pdf](05_wiring/02_AE3_perfboard_drawing.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/p182.pdf) | 基板サイズ確認 |
| 耐熱ワイヤー IRRAX材料参考仕様 | [03_wire_IRRAX_material.pdf](05_wiring/03_wire_IRRAX_material.pdf) | [公開元](https://akizukidenshi.com/goodsaffix/irraxa.pdf) | 販売元の参考資料。AWG24商品の仕様ページも参照 |
| 耐熱ワイヤー AWG24×10色 商品仕様 | [04_wire_AWG24_product.html](05_wiring/04_wire_AWG24_product.html) | [公開元](https://akizukidenshi.com/catalog/g/g110672/) | 採用商品そのものの公開仕様 |
| スミチューブC シリーズ仕様 | [05_SUMITUBE_C_datasheet.pdf](05_wiring/05_SUMITUBE_C_datasheet.pdf) | [公開元](https://www.sei-sfp.co.jp/products/pdf/SUMITUBE-C.pdf) | メーカー公開のスミチューブCカタログ。寸法・収縮・材料仕様 |
| スミチューブC 内径1.5mm 商品仕様 | [06_SUMITUBE_1p5_product.html](05_wiring/06_SUMITUBE_1p5_product.html) | [公開元](https://akizukidenshi.com/catalog/g/g106788/) | 選定寸法の確認 |

## スマホ首掛け・固定・通信ケーブル

| 資料 | 保存ファイル | 出典 | 備考 |
|---|---|---|---|
| 首掛けスマホホルダー 商品仕様 | [01_neck_phone_holder_product.html](06_mounting/01_neck_phone_holder_product.html) | [公開元](https://jp.daisonet.com/products/4549131906646) | 使用iPhoneの寸法・カメラ開口・向きは現物照合 |
| 面ファスナー結束バンド 商品仕様 | [02_hook_loop_bands_product.html](06_mounting/02_hook_loop_bands_product.html) | [公開元](https://jp.daisonet.com/products/4550480325248) | 商品ページは白色。黒色採用時は別商品を確認 |
| USB-C充電通信ケーブル 商品仕様 | [03_USB_C_data_cable_product.html](06_mounting/03_USB_C_data_cable_product.html) | [公開元](https://jp.daisonet.com/products/4550480504599) | 書き込み・デバッグ用。手持ちを流用可 |
