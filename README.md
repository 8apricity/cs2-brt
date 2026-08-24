# cs2-brt

高校の探究活動として、**ひたちBRT第Ⅰ期の導入が沿線地価に及ぼす影響**を調べるための研究リポジトリです。

中心的な研究質問は、次のとおりです。

> ひたちBRT第Ⅰ期の導入は、沿線地域の地価にどのような影響を与えたか。

## 主要ドキュメント

- [研究概要](docs/research_overview.md)
- [介入履歴](docs/intervention_timeline.md)
- [データ台帳](docs/data_catalog.md)
- [識別上の課題](docs/identification_risks.md)
- [分析手法の候補](docs/method_candidates.md)
- [意思決定ログ](docs/decision_logs/README.md)

現在の `_targets.R`、`R/functions.R`、`index.qmd` は、サンプルデータを使う動作確認用の雛形です。ひたちBRTの実分析はまだ実装されていません。

## ディレクトリ構成

```text
.
├── .github/workflows/  # GitHub Actions
├── docs/               # 研究文書、意思決定、参考調査
├── R/                  # 再利用可能な関数
├── data/
│   ├── raw/            # 変更しない取得データ
│   ├── manual/         # 人手で整備した小規模な研究データ
│   └── processed/      # コードから再生成する加工済みデータ
├── scripts/            # 初期化・補助スクリプト
├── tests/testthat/     # 単体テスト
├── _targets.R          # 解析パイプライン（現在は雛形）
├── index.qmd           # Quartoレポート（現在は雛形）
└── renv.lock           # 依存関係の固定
```

## 最初のセットアップ

R でプロジェクトルートを開き、次を実行します。

```r
source("scripts/bootstrap.R")
```

これにより、`renv.lock` に固定された依存パッケージをプロジェクト専用ライブラリへ復元します。
復元処理だけを直接実行する場合は、次のコマンドも使用できます。

```r
renv::restore()
```

## パッケージの追加

解析、テスト、レポート生成などで新しいパッケージを直接使用する場合は、次の順序で追加します。

1. `renv::install("package-name")` でプロジェクト専用ライブラリへインストールする。
2. `DESCRIPTION` の `Imports` にパッケージ名を追加する。
3. `renv::snapshot()` で `renv.lock` を更新する。
4. `renv::status()` で依存関係が同期していることを確認する。

`scripts/bootstrap.R` は `renv.lock` からの復元専用であり、パッケージ追加時には編集しません。

## 日常のワークフロー

```r
# 解析とレポートを更新
targets::tar_make()

# 変更された／古くなった処理を確認
targets::tar_outdated()

# テスト
testthat::test_dir("tests/testthat")

# 静的解析
lintr::lint_dir("R")
lintr::lint_dir("tests")

# コード整形（実行するとファイルを書き換えます）
for (path in c("R", "tests", "scripts")) styler::style_dir(path)
styler::style_file("_targets.R")
```

Quarto レポートは `targets::tar_make()` によって `_site/index.html` へ出力されます。

## データの取り扱い

`data/raw/` の取得データは変更せず、原則としてGit管理しません。人手で整備した小規模な研究データは `data/manual/`、コードから再生成できる加工データは `data/processed/` に置きます。データセットごとの来歴と制約は[データ台帳](docs/data_catalog.md)を参照してください。機密情報や共有できない研究データ、APIキーはGitへ追加しないでください。
