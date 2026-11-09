# 地域別道路データの管理

地域台帳は `Data/regions.json`。配列順が初期地域と共有境界上の優先順位になる。アプリの読み込み、OSM変換、Xcodeリソース生成はこの台帳を共通で使う。

- `key`: 小文字英数字とハイフンの不変キー（例 `kokura`）。原本は `Data/raw/<key>-osm.json`、取得クエリは `Data/raw/<key>-query.txt`、配布データは `Data/<key>-network.json`。
- `networkID`: 報告保存先にも使う不変ID（例 `kokura-ground-osm`）。地域追加時に一意なIDを割り当て、更新時は変更しない。小倉の旧 `real-reports.json` は従来どおり維持する。
- `name`、`bounds`（south/west/north/east）、`destinations`（id/name/latitude/longitude）を指定する。実験接続点は取得範囲内かつ道路ノードから40m以内。施設入口の保証ではない。
- `sourceURL`、`license` を記録する。現変換器はOSM / `ODbL-1.0`専用。別出典は同じ変換器へ混ぜない。

新地域は台帳へ1件追加し、以下の `<key>` をそのキーに置き換える。更新は同じキーで行う。

```sh
# 初回取得・明示的な再取得。既存の原本・クエリ・配布版を先に退避する。
python3 Scripts/build_network.py --region <key> --fetch --output /tmp/<key>-network.json
# 保存済み原本だけで再変換する場合は --fetch を省略する。
# 新規地域（旧版がない場合）は --previous を省略する。
python3 Scripts/validate_network.py /tmp/<key>-network.json --region <key> --previous Data/<key>-network.json
```

変換時と配置前の検証で、ID重複、欠損、非有限座標、範囲、道路端点と形状の一致、参照先、距離、向き、出典、日時を確認する。原本のOSMノード欠落も検出し、不完全なグラフとして黙って取り込まない。失敗時は配布版を置き換えない。`--fetch --output` でも原本の取得・退避は行うが、配布ネットワークは指定した候補パスだけへ出力する。

差分にある `removedIDs` は旧報告が参照できなくなる区間、`changedGeometryOrDirectionIDs` はIDが同じでも形状・方向が変わる区間。対象区間の現地再確認と既存報告への影響をレビューしてから、検証済み候補を `Data/<key>-network.json` に配置する。旧配布版は取得時の `Data/archive/` に残る。`--fetch` なしの候補から配置するときも旧版を先に `Data/archive/` へ保存する。候補を介さず `--output` を省略して再変換する場合も、検証成功後・置換前に旧版を自動退避する。

```sh
python3 Scripts/build_network.py --check
python3 -m unittest discover -s Tests/Scripts -v
python3 Scripts/create_project.py
swift test
```

新地域を含むXcodeプロジェクトをコミットし、Simulatorビルド・地域切替・対象経路・閉鎖時の迂回を確認する。CIも全地域の検証とPythonテストを実行する。道路データだけでなく台帳・原本・クエリ・退避版・更新差分を同じPRでレビューする。

配布JSONの `acquiredAt` は加工版の生成時刻。OSMの基準時刻は `version` の先頭および新規生成版の `provenance.osmTimestamp` に残す。新規生成版は取得元URL、ライセンス、原本SHA-256、変換器版も `provenance` に保存する。新たな `--fetch` は取得日時と実際のAPIエンドポイントを `Data/raw/<key>-metadata.json` に記録し、原本ハッシュが一致する場合だけ `provenance.fetchedAt` / `endpoint` に引き継ぐ。記録のない旧原本の取得日時は不明（null）とし、生成時刻で代用しない。取得メタデータも原本と一緒に退避・コミットする。`version` はOSM基準時刻＋グラフ内容のハッシュなので、同じ原本でも形状・分割・目的地・範囲が変われば報告の版不一致を検出できる。設定の「道路データ」で使用中の地域・出典・版を確認できる。今回の整備では既存配布グラフを更新しない。

版不一致時は既存どおり案内を保留し、報告を自動削除・移行しない。「同じ区間IDの報告だけ引き継ぐ」はID一致を条件にするため、形状が変わった区間を安全と判断する機能ではない。更新差分を確認し、必要なら旧報告を退避して現地で再登録する。どちらの明示操作でも元報告はバックアップに残る。
