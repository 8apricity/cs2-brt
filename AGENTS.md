# OurQuest で作業するAIエージェントへ

このリポジトリは、高校の探究活動として「ひたちBRT第Ⅰ期の導入が沿線地価に及ぼす影響」を調べるための研究環境である。研究に関する作業では、推測を既知の事実として扱わず、一次資料、実データ、ユーザーが明示的に確認した内容を優先する。

## 作業開始時に読む文書

すべての研究作業で、最初に次を読む。

1. [`docs/research_overview.md`](docs/research_overview.md)
2. [`docs/decision_logs/README.md`](docs/decision_logs/README.md)

そのうえで、作業内容に応じて次を読む。

| 作業内容 | 追加で読む文書 |
|---|---|
| BRTの時期・区間・停留所 | [`docs/intervention_timeline.md`](docs/intervention_timeline.md)、必要に応じて[`docs/hitachi_brt_stop_openings_research.md`](docs/hitachi_brt_stop_openings_research.md) |
| データの取得・確認・加工 | [`docs/data_catalog.md`](docs/data_catalog.md) |
| 因果解釈や交絡の検討 | [`docs/identification_risks.md`](docs/identification_risks.md) |
| 分析手法の検討 | [`docs/method_candidates.md`](docs/method_candidates.md)、[`docs/identification_risks.md`](docs/identification_risks.md)、対応する `docs/research/` の参考調査 |
| 研究方針の変更 | [`docs/decision_logs/README.md`](docs/decision_logs/README.md) と関連する個別決定 |
| READMEや概要の更新 | 内容に対応する正本文書 |

## 情報の状態

- `確認済み`：一次資料、実データ、またはユーザーの明示的な確認に基づく。
- `暫定`：現時点の整理であり、追加確認により変更され得る。
- `未確認`：必要性は認識しているが、根拠または実データをまだ確認していない。

すべての文章へ機械的にラベルを付ける必要はない。事実状態が研究判断へ影響する表や記述では、状態を明示する。

## 情報源と正本

事実は可能な限り、発行主体が公開する一次資料または実データで確認し、資料名が分かるMarkdownリンクを記述の近くに置く。同じ詳細情報を複数文書へ複製せず、次を正本とする。

- 研究目的・質問・対象範囲：`docs/research_overview.md`
- 介入時期・区間・停留所変更：`docs/intervention_timeline.md`
- データの仕様・収録状況・来歴：`docs/data_catalog.md`
- 識別上の課題：`docs/identification_risks.md`
- 手法候補と現在の評価：`docs/method_candidates.md`
- 合意済みの研究判断：`docs/decision_logs/`

文書間の優先順位は、次のとおりである。

1. `docs/decision_logs/` にある有効な決定
2. `docs/` 直下の正本文書
3. `docs/research/` の手法別参考調査

矛盾を見つけた場合は、矛盾する記述とファイルをユーザーへ通知し、上位の正本に従う。正本から安全に判断できる場合は作業を続けてよいが、研究対象、介入時点、データの意味、手法の採否、成果の解釈を変え得る矛盾では作業を止めて確認する。許可なく下位文書の内容を正本へ反映しない。

正本文書を更新したときは、参照する概要や一覧に矛盾する古い要約が残っていないか確認する。詳細の複製は増やさず、リンクによって正本へ案内する。

## データの保護

- `data/raw/` のファイルを変更、上書き、名前変更、削除しない。
- 文字コード変換や形式変換はコードで再現し、生成物は `data/processed/` に置く。
- 人手で作成・確認した小規模な研究データは `data/manual/` に置き、根拠を文書化する。
- APIキーやその他の秘密情報をリポジトリへ保存しない。

## 意思決定ログ

AIの推奨や作業上の仮定を、独断で研究上の決定として記録しない。`docs/decision_logs/` に追加するのは、ユーザーが明示的に合意した、将来の研究方針へ影響する判断だけとする。既存の決定を置き換える場合は元の記録を削除せず `置換済み` とし、新しい決定から相互に参照する。

## 現在の解析コード

`_targets.R`、`R/functions.R`、`index.qmd` は、`data/raw/example.csv` を使う動作確認用の雛形である。現時点では、ひたちBRTの実分析を実装したパイプラインではない。
