# 電源ボタン専用版

`CaneVibePower.ino` 1ファイルで使用できます。`CaneControl.h`は不要です。添付のStep6で使っているD0ボタンを、電源ON/OFFだけに割り当てています。

| 状態 | 操作 | 結果 |
|---|---|---|
| 動作中 | 1回押して離す | 振動とBLEを停止し、System OFFへ移行 |
| System OFF中 | 1回押す | 再起動してBLE広告を再開 |

長押しの専用動作、振動通知のON/OFF切替、振動テストはボタンに割り当てていません。BLEと注意・危険に応じた振動の機能は元のコードを維持しています。

## 接続と書き込み

- ボタンは **XIAOのD0とGNDの間**。`INPUT_PULLUP`を使います。D0はnRF52840のP0.02であり、物理GPIO番号0ではありません。
- テストスクリプトに合わせて `BUTTON_PIN=0` としています。実物のボタンがD0以外につながっている場合は、この値を実際の配線に合わせてください。
- DRV2605Lは元どおりD4/SDA、D5/SCLを使います。
- Arduino IDEの **Seeed nRF52 Boards → Seeed XIAO nRF52840 Sense** を選び、このフォルダの`CaneVibePower.ino`を開いて書き込みます。mbed版ではありません。
- 必要なライブラリは元と同じAdafruit DRV2605 Library、Adafruit BusIO、およびボード付属のBluefruit/TinyUSBです。
- 電源投入・リセット後はONで起動します。復帰のために押したボタンを離しても、再びOFFにならないようにしています。
- OFF後の次の押下で起動したら、iOSアプリから白杖を再検索・接続してください。

## OFFの意味と検証範囲

ここでのOFFはnRF52840の **System OFF（省電力停止）** です。電池を物理的に切り離す機能ではありません。DRV2605Lには振動停止とSTANDBYを指示します。USB・充電回路・接続機器全体の消費電流がゼロになる保証はありません。

停止前にBLE広告を止めて接続を解除し、ボタンを離してからGPIO SENSEによる復帰を設定します。System OFFからの復帰はリセット起動です。参考：[Nordic nRF52840 POWER](https://docs.nordicsemi.com/r/bundle/ps_nrf52840/page/power.html)。

Sense向けコンパイルと、ボタンの1回押し・離す待ち・復帰時の押下の無視・30msのチャタリング除去・時刻の周回のホストテストを実施しています。基板への書き込み、実機でのSystem OFF・ボタン復帰・消費電流は未確認です。USB接続中と電池駆動時は別々に動作確認してください。

ホストテストはリポジトリルートから実行します。

```sh
clang++ -std=c++11 -Wall -Wextra -Werror Firmware/Tests/PowerButtonTests.cpp -o /tmp/cane-power-button-tests
/tmp/cane-power-button-tests
```
