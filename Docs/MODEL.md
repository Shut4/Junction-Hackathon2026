# モデルの記録

- 現行モデル: `vidvipo_yolov8x_2023-05-19.mlmodel`（`App/Info.plist` の `JGDetectionModel` で指定）
  - SHA-256: `56b6d6d7069655e1aaea654bb14465f6b773827e1b9138db01d617b0371273ea`
  - サイズ: 約260 MB（.mlmodel / コンパイル後の .mlmodelc とも）
  - 2026-09-26、検出精度の向上を目的に、ユーザー指定の配布ファイル（ローカル保存。パスはリポジトリに記録しない）へ変更。入力・出力・39クラスの名前と順序・NMS込みパイプライン・メタデータ（Ultralytics 8.0.105、AGPL-3.0表記）はyolov8nと同一であることをMacで確認。Macでの単発推論は約0.05秒。iPhoneでの推論速度・メモリ・熱・電池は未評価。
- 初期モデル: `vidvipo_yolov8n_2023-05-19.mlmodel`（`JGDetectionModel` を戻して `install_model.sh` を実行すれば再び使用できる）
  - SHA-256: `b672199b227020b7f8b2bcc160f542b7151fdce837bff97eac42c13fc7dd30d3`
  - 2026-09-26、ユーザーからハッカソンでの利用指示を受け、ローカルでコンパイル・実験端末への同梱を実施。
- 入力画像: 640×640。任意入力に`iouThreshold`、`confidenceThreshold`。
- 出力: `confidence`、`coordinates`（画像に対するx/y/width/height）。モデルはNMSを含むパイプライン。既定の信頼度0.25、IoU0.45の記述あり。アプリの通知閾値0.6は別の処理。
- Vision: `.scaleFit`で画像方向`.right`の背面・縦固定を第一実装。首掛け時の画角・余白処理・姿勢は評価待ち。
- 実際のVision出力は`VNRecognizedObjectObservation`として読み取り可能。Macで均一な入力に対する推論の実行を確認したが、物体検出精度の評価ではない。
- 端末内の低頻度推論（上限およそ6.7回/秒）、継続判定、クラスと画像内枠の重なりによる短時間対応付け、クラス単位の通知間隔を組み合わせる。
- 画像内位置は実距離・身体に対する左右を示さない。障害物検出から通行不可を自動登録しない。

39クラス:

```
person bicycle car motorbike bus train truck boat traffic_light bicycler
braille_block guardrail white_line crosswalk signal_button signal_red signal_blue
stairs handrail steps faregates train_ticket_machine shrubs tree vending_machine
bathroom door elevator escalator bollard bus_stop_sign pole monument fence wall
signboard flag postbox safety-cone
```

通知対象の初期集合は `pole / stairs / steps / bollard / safety-cone / person / bicycle`。信号色から横断可否を案内しない。

## 条件の確認記録

[VIDVIP公式](https://tetsuakibaba.jp/project/vidvip/#models)と[申請フォーム](https://forms.gle/6Nk7aJFQPmbEyTqj7)はCC BY-NC-ND 4.0表記。一方、ユーザー指定ファイルのMLModelMetadataには `AGPL-3.0 https://ultralytics.com/license` とUltralytics 8.0.105の記述がある。ファイル内の条件と提供元の条件の関係、取得申請での回答、公開・再配布時の扱いは未確認として記録する。ユーザーの実験利用指示を、権利者からの回答として記録していない。

原本の変換・量子化・追加学習は実施していない。外部SDKは追加していない。モデルは同じVIDVIP配布元のyolov8n→yolov8xへの変更のみ。モデルはGit対象外で、公開や第三者への配布を行っていない。アプリUIに利用条件の入力や申請画面を設けていない。

## 評価

単一モデル＋通知抑制を初期構成とする。クラス別の見逃し・誤警告、通知回数/分、推論/通知遅延、メモリ、熱、電池を同じ条件で測定する。通知精度とフレーム単位の物体検出Precision/Recallは別指標。正解アノテーションなしにPrecision/Recallを作らない。信頼度を実環境の正解確率として表示しない。

[BlindNav](https://github.com/Anthonyiswhy/blind_navigation_aid)は継続・通知・計測の考え方だけを参考にし、コードを依存に追加していない。[SANPO](https://github.com/google-research-datasets/sanpo_dataset)は将来候補、[GuideDog](https://github.com/jun297/GuideDog)は短い説明の参考。双方のデータ取得・組み込みは未実施。
