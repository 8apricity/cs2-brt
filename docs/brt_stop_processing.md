# BRT停留所データ加工仕様

この文書は、手作業で整備したひたちBRT停留所履歴と国土数値情報の2022年
バス停留所XMLを結合し、`data/processed/`の停留所点データを再生成する方法と
変換規則を示す。収録状況と来歴の正本は[データ台帳](data_catalog.md)、停留所の
開業履歴の根拠は
[ひたちBRT停留所別開業時期調査](hitachi_brt_stop_openings_research.md)とする。

## 対象と正本入力

次の3ファイルを入力とする。

- `data/manual/brt_stop_history.csv`：42件の停留所履歴とXML照合名
- `data/raw/bus_stops/P11-22_08_GML/P11-22_08_GML/P11-22_08.xml`：
  2022年の公式停留所名、運行事業者、座標
- `data/manual/brt_stop_coordinate_validation.csv`：歴史停留所についてユーザーが
  確認した座標と確認方法

一時的なBRT停車休止は、停留所を一意に保つこの加工処理へ同じ`stop_id`の複数行として
混在させない。`data/manual/brt_stop_service_interruptions.csv`に別表として記録し、
分析時にprocessed停留所表と組み合わせる。現在はサンピア日立の2021年2月～
2022年4月の経由休止1件を収録する。分析列への反映は
[BRT処置列の探索実装メモ](exploration_treatment_design.md)を参照する。

geometryの正本は公式XMLとし、手動確認座標で上書きしない。手動確認座標は、
公式XMLの2022年座標が歴史的位置と整合するかを記録するために使う。

## XMLの読取りと結合

XMLの`EnvelopeWithTimePeriod@srsName`が`JGD2011 / (B, L)`であることを検証してから、
`BusStop/loc`参照を`Point`の`gml:id`へ解決し、`gml:pos`を緯度・経度の順で読む。
履歴表の`xml_name`とXMLの`bsn`を完全一致で結合する。processedのgeometryはJGD2011
（EPSG:6668）のPOINTとする。

2026年8月27日の実データ処理では、履歴42件がそれぞれ2022年XMLの1地物へ一意に
結合した。対象内の同名と同一座標はなかった。XML全体の同名停留所には対応しない
ため、管理済みの`xml_name`以外を一般的な名称結合へ流用しない。

`phase1_initial`は、次の両方を満たす11停留所を`TRUE`とする。

- `start_date == 2013-03-25`
- `phase`が`phase1`または`historical_phase1`

## 歴史的位置の状態

`coordinate_source`と`historical_validation_status`を分けて保持する。

| 状態 | 意味 |
|---|---|
| `user_verified` | 手動検証表に確認記録があり、歴史的位置と公式XML座標の整合をユーザーが確認した |
| `provisional` | 第Ⅰ期当初停留所だが、2022年座標を歴史的位置として独立検証していない |
| `not_required_for_phase1_analysis` | 第Ⅰ期当初11停留所ではなく、今回の主分析では歴史的位置の検証対象外 |

中沢（H1）と旧・大甕駅前（H2）はGoogle Street Viewでユーザーが確認した。確認座標と
公式XML座標の距離はそれぞれ約5.8m、約26.4mであり、`user_verified`とする。
第Ⅰ期当初停留所のうち現存9件は`provisional`のままである。これは公式データの
座標が不正確という意味ではなく、2013年当時も同じ位置だったことを別資料で確認して
いないという意味である。

## 出力

成果物はGit管理しない。

- `brt_stops.gpkg`
  - `stops`：JGD2011のPOINTと停留所履歴、来歴、歴史的位置の確認状態
- `brt_stops.csv`：同じ属性と経度・緯度
- `brt_stops_quality.csv`：件数、状態別件数、座標範囲、重複座標、検証距離

主な列は次のとおりである。

| 列群 | 列 |
|---|---|
| 履歴 | `stop_id`、`stop_name`、`xml_name`、`start_date`、`end_date`、`phase`、`current`、`confidence`、`phase1_initial` |
| XML来歴 | `source_feature_id`、`source_point_id`、`source_operator`、`source_dataset`、`source_year`、`coordinate_source` |
| 歴史的位置 | `historical_validation_status`、`historical_validation_method`、`historical_validation_source`、`historical_validation_date`、`historical_validation_by`、確認座標、注記、公式座標との差 |
| 空間 | GeoPackageの`geometry`、CSVの`longitude`と`latitude` |

## 品質検査

次の場合は処理を失敗させる。

- 履歴が42件、現行停留所が25件、第Ⅰ期当初停留所が11件でない
- `stop_id`または管理済み`xml_name`が欠損・重複している
- 管理済み`xml_name`がXMLの0件または複数件に一致する
- XMLのPoint参照を一意に解決できない
- 日付、座標、CRSまたはgeometryが不正である
- 歴史停留所H1・H2に検証記録がない
- 検証元、方法、確認主体、確認日または確認座標が欠けている

同一座標はバス停留所データ全体では起こり得るため、一律の失敗条件にはしない。
対象42件内の重複グループ数を品質レポートへ記録する。

## 実行

プロジェクトルートで次を実行する。

```r
targets::tar_make(names = brt_stop_outputs)
```

3成果物はステージング先で検証してから一括置換する。CIでは実rawを使わず、
`tests/fixtures/brt_stops/`の架空値による最小XML・CSVで公開処理関数とtargets構成を
検証する。

## 利用上の制約

- 2022年XMLには方向別の乗降位置がなく、1停留所1点として扱う。
- この成果物は停留所点であり、2013年の運行経路を表さない。
- `provisional`の9停留所を2013年の厳密な位置として扱う場合は、追加検証が必要である。
- Google Street Viewによる確認はユーザー確認済み情報であり、公式一次資料ではない。
- `current`と単一の`start_date`・`end_date`だけでは途中の運行休止を表さない。
  時点別の稼働判定では手動の休止表も併用する。
