# 意思決定ログ

このディレクトリは、将来の研究方針へ影響する、ユーザー合意済みの判断を1件1ファイルで記録する。作業日誌、AIの提案だけの事項、通常の実装詳細は記録しない。

## 読み方

- `採用`：現在有効な決定。
- `置換済み`：後の決定により置き換えられた決定。削除せず、新旧の決定を相互にリンクする。
- 連番は決定IDであり、後から振り直さない。
- 一覧で現在の方針を確認し、理由や再検討条件が必要なときに個別ファイルを読む。

## 一覧

| ID | 状態 | 決定の要約 | ファイル |
|---|---|---|---|
| 0001 | 採用 | 当面の研究対象をひたちBRT第Ⅰ期とする | [0001-focus-on-phase-1.md](0001-focus-on-phase-1.md) |
| 0002 | 採用 | 実データの状況を十分に確認する前に分析手法を固定しない | [0002-defer-method-selection.md](0002-defer-method-selection.md) |
| 0003 | 採用 | 地価公示・都道府県地価調査・不動産取引価格情報を区別する | [0003-distinguish-price-sources.md](0003-distinguish-price-sources.md) |
| 0004 | 採用 | 研究概要では沿線地域の距離閾値を固定しない | [0004-do-not-fix-distance-threshold.md](0004-do-not-fix-distance-threshold.md) |
| 0005 | 採用 | 対照群の候補を日立市内に限定しない | [0005-allow-controls-outside-hitachi.md](0005-allow-controls-outside-hitachi.md) |
| 0006 | 採用 | 主仮説の方向を限定しない | [0006-use-direction-neutral-hypothesis.md](0006-use-direction-neutral-hypothesis.md) |
| 0007 | 採用 | 第Ⅰ期主分析を当初11停留所・2000～2015年とし、期間別に完全パネルを作る | [0007-define-phase1-analysis-periods.md](0007-define-phase1-analysis-periods.md) |

## 更新規則

AIエージェントは、ユーザーが明示的に合意した研究上の判断だけを追加する。既存決定を変える場合は元ファイルを `置換済み` にし、新しい決定ファイルを追加する。補足や誤字修正は新しい決定を作らず、既存ファイルを修正する。
