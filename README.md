# OurQuest

`targets`、`renv`、`testthat`、`lintr`、`styler`、Quarto を使う、小規模で再現可能な
研究プロジェクトの雛形です。

## 最初のセットアップ

R でプロジェクトルートを開き、次を実行します。

```r
source("scripts/bootstrap.R")
```

これにより、依存パッケージをプロジェクト専用ライブラリへ導入し、
`renv.lock` に固定します。以後、別の環境では次のコマンドで復元できます。

```r
renv::restore()
```

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

## ディレクトリ構成

```text
.
├── .github/workflows/  # GitHub Actions
├── R/                  # 再利用可能な関数
├── data/
│   ├── raw/            # 変更しない入力データ
│   └── processed/      # 必要に応じて保存する加工済みデータ
├── scripts/            # 初期化・補助スクリプト
├── tests/testthat/     # 単体テスト
├── _targets.R          # 解析パイプライン
├── index.qmd           # Quarto レポート
└── renv.lock           # 依存関係の固定
```

機密情報や共有できない研究データは Git に追加しないでください。必要に応じて
`data/raw/` の対象ファイルを `.gitignore` に追記し、取得方法だけを README に記録します。
