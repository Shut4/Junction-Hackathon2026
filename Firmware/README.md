# 白杖のArduinoコード

通常は、電源ボタン付きの **[CaneVibePower](CaneVibePower/README.md)** を使用します。XIAO nRF52840がiPhoneからBluetoothで注意・危険の状態を受け取り、DRV2605Lを通じてLRAを振動させます。

| スケッチ | 内容 |
|---|---|
| [CaneVibePower/CaneVibePower.ino](CaneVibePower/CaneVibePower.ino) | 電源ボタン付き。1ファイルで使用可能 |
| [CaneVibe/CaneVibe.ino](CaneVibe/CaneVibe.ino) | 電源ボタンなし。同じフォルダの `CaneControl.h` が必要 |

注意は長めの単発、危険は短い3連続のリズムです。検出なし・検知不能・切断・指示の途絶時は振動を停止します。

書き込みは[電源ボタン付き版の手順](CaneVibePower/README.md)、通信形式は[Bluetooth仕様](../Docs/BLUETOOTH.md)を参照してください。スケッチを変更するときは、このリポジトリ内のファイルを更新します。

制御・電源ボタンのホストテストは、リポジトリのルートから実行します。

```sh
clang++ -std=c++11 -Wall -Wextra -Werror Firmware/Tests/CaneControlTests.cpp -o /tmp/cane-control-tests
/tmp/cane-control-tests
clang++ -std=c++11 -Wall -Wextra -Werror Firmware/Tests/PowerButtonTests.cpp -o /tmp/cane-power-button-tests
/tmp/cane-power-button-tests
```

これらのテストはBLE無線通信やモーターの実振動を確認するものではありません。
