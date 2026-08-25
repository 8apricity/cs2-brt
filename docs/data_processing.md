# 地価データ加工仕様

この文書は、地価公示と都道府県地価調査の取得済みファイルから、
`data/processed/` の標準データを再生成する方法と変換規則を示す。
収録状況と来歴の正本は[データ台帳](data_catalog.md)、列単位の契約は
[`config/land_price_columns.csv`](../config/land_price_columns.csv)、年度別タグ・
コード対応は
[`config/land_price_mappings.yml`](../config/land_price_mappings.yml)とする。

## 対象

対象年度、観測数、基準日、取得履歴は正本である[データ台帳](data_catalog.md)を参照する。
現在保有する茨城県ファイルの全観測を処理し、日立市や分析期間への抽出は行わない。
両資料は同じ列契約を使うが、基準日と地点集合が異なるため別ファイルとして保持する。

## 正本入力と照合

公式配布XMLを正本入力とし、同梱Shapefileを独立照合に使う。XMLを正本とするのは、
全年度がUTF-8で、意味のある要素名、地点番号の構造、座標参照を保持するためである。
古いShapefileにはCRSや文字コード指定がないものがある。

各年度について、XMLとShapefileの次を照合し、不一致なら処理を失敗させる。

- 行数
- 行政区域コード・用途区分番号・連番の多重集合
- 価格
- 座標（JGD2011へ変換後、差が`1e-7`度以下）

公式地点番号の組合せは一部年度で重複することを実データで確認した。このため
`observation_id` は資料種別、年度、公式地点番号、XML地物IDを組み合わせる。
年度横断の地点同定は行わない。

入力仕様の根拠は国土数値情報の
[地価公示製品仕様第2.1版](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L01-v2_1.pdf)、
[地価公示製品仕様第4.0版](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L01-v4_0.pdf)、
[都道府県地価調査製品仕様第2.1版](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L02-v2_1.pdf)、
[都道府県地価調査製品仕様第4.0版](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L02-v4_0.pdf)
および各年度の同梱メタデータで確認した。

## 座標系

| 資料 | 年度 | 入力CRS | 出力CRS |
|---|---:|---|---|
| 地価公示 | 1983–2023年 | JGD2000（EPSG:4612） | JGD2011（EPSG:6668） |
| 地価公示 | 2024–2026年 | JGD2011（EPSG:6668） | JGD2011（EPSG:6668） |
| 都道府県地価調査 | 1983–2022年 | JGD2000（EPSG:4612） | JGD2011（EPSG:6668） |
| 都道府県地価調査 | 2023–2025年 | JGD2011（EPSG:6668） | JGD2011（EPSG:6668） |

XMLの座標は緯度・経度の順である。processedの観測表には変換後のgeometryまたは
経度・緯度だけを収録し、元EPSGと変換前座標は行ごとに複製しない。元EPSGは
資料種別×年度の`source_metadata`に記録し、元座標値は変更しないraw XMLに残す。

## 出力

各資料について次の5ファイルを生成する。生成物はGit管理しない。

- `{dataset}.gpkg`
  - `observations`：JGD2011のPOINTと中核属性
  - `attributes`：中核表に含めないXML属性の縦長表
  - `source_metadata`：年度別入力仕様とCRS
- `{dataset}_observations.csv`：中核属性とJGD2011経緯度
- `{dataset}_attributes.csv`：縦長属性
- `{dataset}_source_metadata.csv`：年度別入力仕様とCRS
- `{dataset}_quality.csv`：年度別件数、欠損、価格・座標範囲、照合結果

`dataset` は `land_price_publication` または
`prefectural_land_price_survey` である。

## 正規化規則

- 公表された名目価格を円／平方メートルで保持し、物価調整は行わない。
- `location`（所在および地番）と`residential_address`（住居表示）を区別する。
- 現況利用などの複数値はJSON配列で保持する。
- 建物、設備、画地、道路、交通、法規制は原値を保持し、安全に変換できる場合だけ
  正規化値を作る。
- 特殊値は実測値に変換せず、`*_status`へ意味を記録する。
- 一意に変換できない値は正規化列を`NA`とし、`unmapped`または`ambiguous`を使う。
- 高度地区など安全に共通化しない属性は`attributes`へ保持する。公式XMLにある
  `altitudeDistrict`と`altitudeDistric`の両方を受け入れる。

### 基準地価2013年の道路幅員

公式の[2013年データ詳細ページ](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L02-2013.html)
の単位表記はcmだが、ローカル実値の範囲と次版の
[製品仕様第2.3版](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L02-v2_3.pdf)
はmを示す。このため、2013年の値はmと暫定解釈し、
`front_road_width_status = inferred_unit_m`を付ける。原値は
`front_road_width_raw`に保持する。単位を確定できる追加の一次資料が得られた場合は
この扱いを再検討する。

## 実行と失敗時の扱い

プロジェクトルートで次を実行する。

```r
targets::tar_make()
```

`targets`はraw配下の全構成ファイルと5成果物をファイルターゲットとして追跡する。
必須値欠損、重複観測ID、非正価格、無効座標、年度不足、未知スキーマ、
Shapefile不一致では失敗する。全年度の検証とステージング書出しが完了してから
同一資料の5成果物を一括置換し、不完全な正式成果物を残さない。

CIには実rawを置かない。各スキーマ期と既知の例外を再現する架空値の最小XMLを
`tests/fixtures/land_price/`に置き、公開境界のテストと`tar_validate()`を実行する。
実データ全年度の処理と照合はローカルの`tar_make()`で行う。
