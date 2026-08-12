# ひたちBRTの段階開業を利用したDID／イベントスタディ

> **位置づけ：参考資料・適用可能性未検証**
> この文書は分析手法の参考調査である。ひたちBRTの実データについて、年度別標本数、継続地点、対照候補、空間配置などを十分に確認する前に作成された。本文中の「推奨」「主分析」「適性」などの評価は現在の研究方針では確定事項ではなく、手法候補の採否は未評価である。現在の位置づけは [`docs/method_candidates.md`](../method_candidates.md) と有効な[意思決定ログ](../decision_logs/README.md)を正本とする。

調査日: 2026-08-12
対象: 候補2「第I期・第II期の段階開業を利用したDID」
調査方針: 査読論文、著者公開原稿、公式R文書、日立市・国土交通省の一次資料を優先した。

## 結論

この設計は実施可能だが、**2013年・2018年・2019年をそのまま三つの対等な処置コホートにするべきではない**。

- 吸収的な二値処置を「初めてBRT停留所へ近接したこと」と定義するなら、主要コホートは第I期と2018年の第II期先行運行である。
- 2019年の本格運行は、2018年からBRTを利用できた地点の多くにとって新規処置ではなく、専用道接続、経路変更、停留所新設を伴う**処置強度の上昇**である。通常のstaggered DIDは、処置が一度始まると継続する吸収的処置を前提にするため、2019年を同じ個体の「新しい初回処置年」として再登録できない。[Sun and Abraham (2021)](https://arxiv.org/abs/1804.05785)
- 中間発表では、Callaway–Sant'Anna型の `ATT(g,t)` により、まず**第I期コホートの効果**を報告するのがよい。第II期予定地域は、自らが処置される直前まで同一市内の not-yet-treated 対照として使える。ただし、計画公表による先取り、連続した沿線間の波及、東日本大震災後の復興差が重大な識別上の脅威である。
- したがって本手法の位置づけは、単独で決定的な主分析というより、**第I期DIDを改善する補助的／準主分析**が妥当である。少数の地価地点と実質二つの処置波しかないため、点推定よりも、コホート別推定値、同時信頼帯、事前トレンド、地点数、対照群の変化、感度分析を重視する。

## 1. 推定対象（estimand）

地価地点 $i$ が初めて処置後となる観測期を $G_i=g$、時点 $t$ の対数地価を $Y_{it}$ とする。中心となる推定対象は、

\[
ATT(g,t)=E\left[Y_{it}(g)-Y_{it}(\infty)\mid G_i=g\right]
\]

である。これは「観測期 $g$ に初めてBRT近接地点となった標準地・基準地について、時点 $t$ の地価が、BRT近接地点にならなかった場合より平均でどれだけ変わったか」を表す。Callaway and Sant'Annaは、処置時期が異なる多期間DIDでこの group-time ATT をまず推定し、コホート、暦年、イベント時点などに集約する枠組みを示している。[Callaway and Sant'Anna (2021)](https://arxiv.org/abs/1803.09015)

本研究で優先すべき推定対象は次の順である。

1. **第I期コホート別効果**: $ATT(g_I,t)$。研究課題が第I期なので、これが主要estimandである。
2. **第I期の初期・中期平均効果**: 例として開業後1～3年、4～5年を事前に固定して平均する。個々の年の標準誤差が大きい場合にも解釈しやすい。
3. **段階開業全体のイベント時点効果**: 同じ経過年 $e=t-g$ の `ATT(g,t)` をコホート間で平均する。ただし経過年が長くなるほど第I期だけが残り、平均の構成が変わる。`did::aggte(..., type="dynamic", balance_e=...)` は、所定の経過年まで観測できるコホートに標本を揃える機能を持つ。[did `aggte` documentation](https://www.rdocumentation.org/packages/did/versions/2.5.0/topics/aggte)

この効果は、実際にBRTを利用した人への効果ではない。処置を停留所からの距離で割り当てるため、解釈は「指定距離内にBRTアクセスが設けられたこと」の地価への効果、すなわち地理的な割当てに対するITTに近い。処置半径は500m、800m、1,000m、1,500m等で結果が変わり得るため、一つを主仕様として事前に固定し、他を感度分析にする。

## 2. 開業事実と、観測データ上のコホート年

日立市資料によれば、第I期は2013年3月25日に道の駅日立おさかなセンターから大甕駅東口まで運行を開始した。2018年3月26日に常陸多賀駅まで先行運行を開始したが、一部は一般道を通る暫定ルートだった。2019年4月1日には大甕駅西口経由の本格運行となり、南部図書館から河原子（BRT）まで約6.1kmの専用道が接続された。[日立市「まちづくりかわら版 第4号」](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/002/793/04804_20130607_0001.pdf) [日立市「ひたちBRTが本格運行」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002786.html) [日立市「常陸多賀駅まで運行開始」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002787.html)

一方、地価公示の価格時点は毎年1月1日、都道府県地価調査は毎年7月1日である。したがって「運行開始年」ではなく、各データで初めて開業後の価格を観測する年を `gname` に入れる必要がある。[国土交通省「主な公的土地評価一覧」](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000042.html)

| 変化 | 実日付 | 地価公示で最初の処置後年 | 地価調査で最初の処置後年 | 扱い |
|---|---:|---:|---:|---|
| 第I期運行開始 | 2013-03-25 | 2014 | 2013 | 主要な初回処置コホート |
| 日立商業高校停留所追加 | 2016-02-01 | 2017 | 2016 | 小規模な追加コホート、又は感度分析で除外 |
| 第II期先行運行 | 2018-03-26 | 2019 | 2018 | 第II期の主要な初回処置コホート |
| 第II期本格運行 | 2019-04-01 | 2020 | 2019 | 新規停留所の純粋な新規アクセスだけをコホート化。既処置地点の強化は別分析 |

日立商業高校停留所の2016年2月1日という日付は、リポジトリ内の既存調査で確度「中」とされている。日立市の発表資料は平成28年の追加までは示すが、今回確認した一次資料だけでは月日を再確認できなかったため、この小コホートを使う前に運行事業者の原告知等で再検証する。[日立市発表資料「ひたちBRTの導入から」](https://www.estfukyu.jp/pdf/2025seminar/02_3_hitachi.pdf)

### 推奨する個体別コホート割当て

1. 解析前に処置半径 $r$ を固定する。
2. 各地価地点について、各時点に営業していた停留所までの距離を計算する。
3. 距離 $r$ 内に初めて入った運行開始日を求め、上表に従って「最初の処置後観測年」へ変換する。
4. 複数期の停留所半径が重なる地点は**最も早い年**へ割り当て、その後もそのコホートを変えない。
5. 一度だけBRTが停車した2018年暫定一般道停留所の近隣は、処置が2019年に消えるため、吸収的処置の主分析から除外する。別途「一時的アクセス」として記述する。
6. 2019年新設停留所の半径が2013年又は2018年の処置圏と重なる場合、その地点を2019年コホートへ上書きしない。

この手順を取ると、2019年に純粋な新規コホートとして残る地点は少数又はゼロになる可能性がある。それは失敗ではなく、**本格運行が新規処置ではなく既存処置の質的強化だった**ことをデータ上正しく表す。

## 3. not-yet-treated 対照群を使える期間

`did` パッケージの `control_group="notyettreated"` は、各時点でまだ処置を受けていない将来処置群と、never-treated群を対照に含める。対照群は時点ごとに変わる。[did公式ビネット](https://cran.r-universe.dev/did/doc/did-basics.html) [did `att_gt` source/documentation](https://github.com/bcallaway11/did/blob/master/R/att_gt.R)

開業日のみを基準にして先取り期間を0とした機械的な利用可能期間は次のとおりである。

| データ | 第I期の効果を推定するとき、第II期先行コホートを対照にできる最終年 | 理由 |
|---|---:|---|
| 地価公示 | 2018 | 2018年1月1日は3月26日の先行運行前。第II期の `G=2019` |
| 都道府県地価調査 | 2017 | 2018年7月1日は先行運行後。第II期の `G=2018` |

その後の第I期効果には、処置半径外の never-treated 地点が必要になる。never-treatedを使わず将来処置群だけに依存する仕様では、第II期が始まった後の第I期長期効果は識別できない。

ただし、土地価格は将来の交通整備を期待して開業前に動き得る。日立市は、日立電鉄線跡地の活用方針を2009年3月に定め、2011年1月にはBRTの新交通導入計画を策定したとしている。[日立市「新交通導入計画を策定しました」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html) 第II期も遅くとも2016年策定の地域公共交通網形成計画等で公的に位置づけられていた。[日立市地域公共交通網形成計画](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/002/851/moukeikakukaitei.pdf) よって、開業直前まで将来処置群が完全に未処置だったという仮定は強い。

`att_gt()` の `anticipation=L` は、処置の $L$ 期前から潜在的な先取りを認める。[did `att_gt` source/documentation](https://github.com/bcallaway11/did/blob/master/R/att_gt.R) 主仕様を `L=0` にする場合も、少なくとも `L=1,2,3` を感度分析し、対照として使える末年がどのように短くなるかを明示する。さらに、2011年の計画策定を「情報処置」と見なす別仕様も検討すべきである。ただし、この仕様が推定するのは運行開始だけでなく、計画公表から開業までを含む総効果になる。

## 4. 2019年をどう扱うか

### 主仕様: 初回BRTアクセス

2018年3月に営業を始めた恒久停留所の近隣は、2018年先行運行を初回処置とする。2019年本格運行後も処置済みのままである。この定義で推定するのは「BRTサービスへの初回アクセス」の効果であり、2019年の専用道接続は処置後の強度変化に含まれる。

### 別仕様: 2019年本格運行の増分効果

2019年の増分効果を知りたい場合は、次のいずれかを別の研究設計として行う。

- 新規停留所によって初めて処置圏に入った地点だけを2019年コホートにする。
- 2018年先行運行地域を処置群とし、2019年本格運行を介入時点とした短い2×2 DID又はイベントスタディを組む。ただし、2018年時点ですでに処置済みなので、これは「BRT導入効果」ではなく「専用道接続・経路変更の増分効果」である。
- 一般道から専用道への切替、所要時間・便数・停留所距離などを処置強度として扱う。ただし連続・多値処置DIDは、二値処置DIDとestimand及び仮定が異なるため、中間発表の主仕様にはしない。[Callaway, Goodman-Bacon, and Sant'Anna, continuous treatment paper](https://arxiv.org/abs/2107.02637)

日立市の公式説明でも、2018年は一部一般道の暫定ルートで、2019年は大甕駅西口経由かつ大部分が専用道路でつながる本格運行とされている。この制度差は、2019年を単なる第三の同質コホートとみなせない根拠である。[日立市「常陸多賀駅まで運行開始」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002787.html) [日立市「ひたちBRTが本格運行」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002786.html)

## 5. 単純なTWFEを避ける理由

処置時期が異なるデータに単純な二方向固定効果（unit FE + year FE + treated）を使うと、早期処置群が後期処置群の処置後に対照として使われる。Goodman-Baconは、TWFE係数が処置時期群間の2×2 DIDの加重平均であり、すでに処置された群を対照にする比較が入ること、処置効果が時間とともに変わると不適切な重み付けが生じ得ることを示した。[Goodman-Bacon (2021)](https://doi.org/10.1016/j.jeconom.2021.03.014)

動的TWFEイベントスタディでは問題がさらに深い。Sun and Abrahamは、処置効果がコホート又は経過時間で異なると、特定のlead/lag係数に他の時点の処置効果が混入し、真の先取りがなくても見かけの事前トレンドが生じ得ることを示した。[Sun and Abraham (2021)](https://arxiv.org/abs/1804.05785)

ひたちBRTでは第I期の効果が時間とともに蓄積し、2018～2019年のネットワーク延伸で第I期区間の利便性も変わる可能性が高い。そのため「効果が時点を通じて一定」という単純TWFEに都合のよい条件は特に信じにくい。TWFEは教材的な参考値又はGoodman-Bacon分解の診断としてのみ示し、結論は `ATT(g,t)` 又はinteraction-weighted推定に基づける。

## 6. 推奨推定法とR実装

### 第一選択: Callaway–Sant'Anna

この方法は、各コホート・各時点の `ATT(g,t)` を、never-treated又はnot-yet-treatedと比較して推定し、その後で目的に応じて集約する。結果が第I期、第II期、暦年、経過年のどこから来たかを明示できるため、本研究に最も適している。[Callaway and Sant'Anna (2021)](https://arxiv.org/abs/1803.09015)

```r
library(did)

cs <- att_gt(
  yname = "log_price",
  tname = "year",
  idname = "point_id",
  gname = "first_post_year", # never-treated は 0
  data = land_panel,
  panel = TRUE,
  allow_unbalanced_panel = FALSE,
  control_group = "notyettreated",
  anticipation = 0,
  xformla = ~ 1,
  est_method = "dr",
  bstrap = TRUE,
  biters = 9999,
  cband = TRUE
)

# 第I期・第II期を分けて確認
by_group <- aggte(cs, type = "group")

# 共通のイベント時点だけを比較。数値は支持状況を確認後に固定
dynamic <- aggte(cs, type = "dynamic", min_e = -5, max_e = 5, balance_e = 5)

ggdid(dynamic)
```

`allow_unbalanced_panel=FALSE` は全期間観測できない地点を落としてバランスパネルにする既定動作である。地点の入替えが多い地価データでは、主仕様をバランスパネル、`TRUE` を感度分析とし、各仕様で残る地点を表にする。[did `att_gt` source/documentation](https://github.com/bcallaway11/did/blob/master/R/att_gt.R)

共変量を入れるなら、処置前に固定した用途地域、駅距離、海岸距離、災害浸水、人口構成等に限定する。処置後にBRTの影響を受け得る人口、土地利用、商業集積を同時点値で調整すると、効果の一部を消す「post-treatment control」になり得る。まず `~1` の無条件推定を主結果とし、処置前共変量を使うdoubly robust推定を補助結果にする。

### 第二選択: Sun–Abraham interaction-weighted event study

`fixest::sunab()` はコホート×相対時点の交差項を作り、Sun–Abraham型の集約を実装する。[fixest `sunab` documentation](https://rdrr.io/cran/fixest/man/sunab.html)

```r
library(fixest)

sa <- feols(
  log_price ~ sunab(first_post_year_sa, year, ref.p = -1) |
    point_id + year,
  data = land_panel,
  vcov = ~ spatial_cluster
)

iplot(sa)
aggregate(sa, "att")
aggregate(sa, "cohort")
```

これはCallaway–Sant'Annaとの実装横断チェックに使う。第I期 `ATT(g,t)` を直接追いやすく、対照群と先取り期間を明示できるCallaway–Sant'Annaを主とする。

### 空間相関の感度分析

`fixest::vcov_conley()` は、指定距離以内の空間相関に頑健な分散共分散行列を計算する。[fixest `vcov_conley` documentation](https://lrberge.github.io/fixest/reference/vcov_conley.html) ただし、Conley標準誤差を付ければ少数処置波の問題が解決するわけではない。500m、1km、2km、5km等のcutoffを変え、cluster SEと併記する補助分析に留める。

## 7. 識別上の主要リスク

### 7.1 条件付き平行トレンド

第I期地域と第II期地域は無作為に開業順を割り当てられたわけではない。第I期区間の沿岸性、土地利用、旧鉄道駅、人口減少、開発余地が異なるなら、BRTがなくても地価トレンドが違った可能性がある。将来処置群を同一市内対照にすることは市全体の景気ショックを共有できる利点があるが、開業順の内生性を自動的には解消しない。

### 7.2 東日本大震災と復興

第I期開業の約2年前に東日本大震災が発生した。日立市は住家全壊436棟、大規模半壊706棟、半壊3,283棟等を記録し、久慈川・茂宮川で浸水が発生したとしている。[日立市津波対策計画](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/004/798/1tsunami.pdf) [日立市地域防災計画](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/004/798/jishin01.pdf) 第I期は南部・沿岸側にあるため、2011年後の復旧・復興が第I期と第II期で異なると、2013年以降の差をBRT効果と誤認し得る。

必須対応は、津波浸水実績・被災地域を地図上で重ねること、2011年前後の地価変化をコホート別に描くこと、浸水地点除外、被災度別分析、2011～2013年を含む／除く仕様を比較することである。なお、被災後の回復自体が地域の重要な価格形成要因なので、単なる年固定効果では沿線別の差を除けない。

### 7.3 先取り（anticipation）

2009年の跡地活用方針、2011年1月の新交通導入計画により、住民・不動産市場は開業前にBRTを予想できた。[日立市「新交通導入計画」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html) 地価への効果は、実際の運行開始より計画確定・工事進捗で先に現れる可能性がある。`anticipation=0` のみを報告せず、複数年の先取りを許す。

### 7.4 空間的spilloverと対照群汚染

BRTの便益は停留所半径の境界で急にゼロになるとは限らない。処置圏外の近隣地点や、将来の第II期地域が第I期開業によるネットワーク便益を受けると、対照群も処置され、通常のDIDは直接効果と波及効果を混ぜる。空間的spilloverが対照へ及ぶ場合に標準DIDが偏り得ることは、空間DIDの研究でも示されている。[Butts, “Difference-in-Differences Estimation with Spatial Spillovers”](https://arxiv.org/abs/2105.03737)

対応として、(a) 500–800mを処置、800m–1.5kmをdonutとして除外、1.5–5kmを対照とする仕様、(b) 第I期・第II期の境界付近を除外、(c) 距離帯別効果、(d) 対照の最小距離を変える感度分析を行う。ただし、donutをデータを見て選ばず事前に複数候補として固定する。

### 7.5 同時に起きた他の整備

2019年本格運行は大甕駅西口経由、専用道接続、駅舎工事と関係しており、BRT単独の変化ではない。[日立市「常陸多賀駅まで運行開始」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002787.html) 大甕駅周辺では、駅舎、東西自由通路、西口駅前広場、アクセス道路、BRTを一体的に検討していた。[日立市「大甕駅周辺地区整備計画」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/toshikyotenseibi/1009099/1002784.html) したがって大甕駅周辺の2019年効果は「本格BRTと関連都市整備の束」の効果になりやすい。駅から一定距離内を除外した仕様を必ず出す。

### 7.6 少数コホート・少数処置ショック

地価地点が複数あっても、処置の独立した政策ショックは実質的に第I期と第II期の二つである。典型的なcluster-robust推論は政策変更群が多いことを前提とし、少数の政策変更では別の推論上の注意が必要である。[Conley and Taber (2011)](https://doi.org/10.1162/REST_a_00049) また、通常のwild cluster bootstrapも処置clusterが非常に少ない場合に失敗し得る。[MacKinnon and Webb (2018)](https://doi.org/10.1111/ectj.12107)

`did` の公式ビネットも、小さいコホートの `ATT(g,t)` は漸近近似が不安定になるため、慎重に解釈し、集約効果も検討するよう警告している。[did公式ビネット「Small Group Sizes」](https://cran.r-universe.dev/did/doc/did-basics.html) 本研究ではp値の有意／非有意で結論を二分せず、推定値、同時信頼帯、地点数、実質的な効果量、仕様間の安定性を示す。

### 7.7 連続地点の誤差相関

近い標準地は同じ局地的な住宅市場ショックを受け、同じ地点の年次価格は系列相関する。DIDで系列相関を無視すると標準誤差が過小になり得る。[Bertrand, Duflo, and Mullainathan (2004)](https://doi.org/10.1162/003355304772839588) 地点cluster、空間メッシュcluster、Conley cutoffを比較する。ただし、空間cluster数が少なければcluster SE自体も不安定であることを併記する。

## 8. 診断、placebo、感度分析

### 必須の記述・診断

- 年×コホート×距離帯ごとの地点数、欠測数、継続地点数を表にする。
- コホート地図を作り、第I期・2018先行・2019新規・never-treated・暫定停留所・重複圏を色分けする。
- 対数地価の未調整平均と中央値を、処置時点の縦線付きでコホート別に描く。
- `ATT(g,t)` の全セルを先に出し、第I期のどの年がどの対照群で識別されるかを表にする。
- lead係数は点ごとの95%区間だけでなく、同時信頼帯と事前係数の共同検定を示す。
- pre-trendが有意でなかったことを「平行トレンドが証明された」と解釈しない。通常の事前トレンド検定は検出力が低く、検定通過後の推論にも歪みが生じ得る。[Roth (2022)](https://doi.org/10.1257/aeri.20210236)

### placebo

1. **偽の開業年**: 第I期の実開業前データだけを用い、2008年、2009年、2010年等を偽介入年にする。震災年を跨ぐplaceboは別に表示する。
2. **偽の将来効果**: `ATT(g,t)` の処置前セルが系統的に正負へ動かないか確認する。
3. **偽の沿線**: 旧鉄道・幹線道路等、BRTにならなかった類似軸を事前規則で選び、同じ距離処理を行う。無作為な回転・平行移動は地形・海岸・用途地域を壊すため、参考に留める。
4. **アウトカムplacebo**: BRTで短期には変わりにくい地理的属性が、処置前後で見かけ上変化していないか確認する。変化するなら地点構成の入替えを疑う。

### 感度分析の事前セット

| 論点 | 仕様候補 |
|---|---|
| 処置半径 | 500m、800m、1,000m、1,500m |
| spillover除外 | donutなし、800m–1.5km除外、1–2km除外 |
| 対照 | not-yet + never、neverのみ、市内のみ、類似市を追加 |
| 先取り | 0、1、2、3年、2011計画年基準 |
| 地点標本 | 完全バランス、非バランス、住宅地のみ、駅周辺除外 |
| 災害 | 全標本、津波浸水除外、久慈地区除外、被災度別 |
| 2019 | 初回アクセスのみ、2019新規地点のみ、2019増分を別DID |
| 推定器 | Callaway–Sant'Anna、Sun–Abraham、参考TWFE |
| 推論 | 地点cluster、空間メッシュcluster、Conley複数cutoff |

平行トレンドの小さな逸脱に対して結論がどこまで維持されるかは、Rambachan–Roth型の感度分析を補助的に利用できる。同方法は平行トレンドが厳密に成立すると仮定せず、処置後のトレンド差に制約を置いてrobustな区間を作る。[Rambachan and Roth (2023)](https://doi.org/10.1093/restud/rdad018) R実装は [HonestDiD](https://asheshrambachan.r-universe.dev/HonestDiD) である。ただし、まずコホート別イベントスタディの係数・分散共分散行列を正しく作る必要がある。

## 9. 具体的な実装手順

1. **時間軸を確定する**
   `data/manual/brt_stop_history.csv` を基に、営業開始・終了、恒久／暫定、初回アクセス／強化を区別する。地価公示用と地価調査用に `first_post_year` を別々に作る。

2. **地点パネルを作る**
   地点IDの継続性を検証し、価格を実質化するか、少なくとも年固定効果で全国・県の共通変化を除く。目的変数は `log(price_yen_m2)` とし、用途区分を保持する。

3. **処置距離を付ける**
   各時点で有効な恒久停留所までの最短直線距離を計算する。主仕様の半径、各感度半径、暫定停留所距離、JR駅距離も保存する。

4. **吸収的な最初の処置年を作る**
   各地点を最も早い処置年へ固定する。2018年一時停留所だけに近い地点は主分析から除外フラグを立てる。2019年は純粋な新規アクセス地点だけを新コホートにする。

5. **支持状況を監査する**
   各 `G` と年の地点数、対照地点数、用途、処置前地価、人口・土地利用を比較する。共変量の重なりが乏しい `ATT(g,t)` は推定しない。`did` も小さい群、特異な共変量行列、overlap違反で `NA` を返し警告する。[did公式ビネット](https://cran.r-universe.dev/did/doc/did-basics.html)

6. **主推定を行う**
   地価公示と都道府県地価調査を混ぜず、別々に `att_gt()` を実行する。第I期 `ATT(g_I,t)`、第I期の事前平均・事後平均、コホート別集約を保存する。

7. **診断を自動生成する**
   地図、未調整トレンド、イベントスタディ、同時信頼帯、事前係数共同検定、地点数、対照構成を一つのQuartoレポートに出す。

8. **感度グリッドを回す**
   半径×donut×anticipation×対照×災害除外×標本の結果を一表にし、符号・大きさ・区間がどこで変わるか示す。最も都合のよい仕様だけを選ばない。

9. **2019増分分析を分離する**
   初回アクセスDIDの結果と、2019本格運行の増分DIDを同じ係数として平均しない。章・図・estimandを分ける。

10. **結論の強さを制限する**
    「有意でない＝効果なし」ではなく、推定可能な効果の範囲、最小検出可能効果、少数地点・少数処置波、先取り、災害復興、spilloverの限界を書く。

## 10. 実現可能性と研究内での役割

### 強み

- 第II期予定地域を開業前まで同一市内の対照にでき、市全体に共通する景気・人口ショックを年固定効果で除きやすい。
- 第I期と第II期の効果を混ぜず、`ATT(g,t)` として可視化できる。
- 開業日が公式資料で確認でき、地価公示・地価調査の評価日との対応も明確に作れる。
- Callaway–Sant'AnnaとSun–Abrahamという査読済みの推定枠組みとR実装がある。

### 弱み

- 実質的な主要処置波は二つで、2019年は処置強化である。staggered rolloutの豊富な時期変動はない。
- 標準地・基準地の処置地点数が少なく、コホート別の漸近推論が弱い。
- 2011年以前から計画が公表され、地価の先取りが強く疑われる。
- 第I期と第II期は連続区間なので、将来処置群へのspilloverが起きやすい。
- 第I期直前の東日本大震災と復興、2019年の大甕駅関連整備が処置時期と重なる。
- 第II期が開業した後の第I期長期効果は、処置圏外のnever-treatedに強く依存する。

### 推奨する位置づけ

この方法は、**「第I期の固定地点イベントスタディDID」を、将来処置される第II期地域で補強する準主分析**として用いるのがよい。第I期研究という目的に対し、段階開業全体の平均効果を主題へすり替えず、第I期 `ATT(g_I,t)` を前面に出す。

中間発表での最低成果物は次の5点とする。

1. 評価日を反映したコホート地図と地点数表。
2. 第I期対第II期予定地域の未調整地価トレンド。
3. Callaway–Sant'Annaによる第I期 `ATT(g_I,t)` と同時信頼帯。
4. 先取り、距離帯、災害地域除外、never-treatedのみの感度分析。
5. 2019年を「第三コホート」ではなく「強化」と分けた識別図。

結果が距離、対照、災害除外で大きく変わる場合、本手法を主たる因果証拠とはせず、記述的・探索的結果として扱う。一方、地価公示と都道府県地価調査で方向が一致し、複数の対照・先取り・spillover仕様でも安定するなら、他の手法を補強する重要な証拠になる。

## 主要一次資料

### 方法論

- Callaway, B. and Sant'Anna, P. H. C. (2021), “Difference-in-Differences with Multiple Time Periods.” [著者公開原稿](https://arxiv.org/abs/1803.09015), [DOI](https://doi.org/10.1016/j.jeconom.2020.12.001)
- Sun, L. and Abraham, S. (2021), “Estimating Dynamic Treatment Effects in Event Studies with Heterogeneous Treatment Effects.” [著者公開原稿](https://arxiv.org/abs/1804.05785), [DOI](https://doi.org/10.1016/j.jeconom.2020.09.006)
- Goodman-Bacon, A. (2021), “Difference-in-Differences with Variation in Treatment Timing.” [DOI](https://doi.org/10.1016/j.jeconom.2021.03.014)
- Roth, J. (2022), “Pretest with Caution.” [AEA掲載ページ](https://doi.org/10.1257/aeri.20210236)
- Rambachan, A. and Roth, J. (2023), “A More Credible Approach to Parallel Trends.” [DOI](https://doi.org/10.1093/restud/rdad018)
- Butts, K., “Difference-in-Differences Estimation with Spatial Spillovers.” [著者公開原稿](https://arxiv.org/abs/2105.03737)
- Conley, T. G. and Taber, C. R. (2011), “Inference with Difference in Differences with a Small Number of Policy Changes.” [DOI](https://doi.org/10.1162/REST_a_00049)
- MacKinnon, J. G. and Webb, M. D. (2018), “The Wild Bootstrap for Few (Treated) Clusters.” [DOI](https://doi.org/10.1111/ectj.12107)
- Bertrand, M., Duflo, E., and Mullainathan, S. (2004), “How Much Should We Trust Differences-in-Differences Estimates?” [DOI](https://doi.org/10.1162/003355304772839588)

### 制度・データ

- 日立市「[ひたちBRTが常陸多賀駅まで運行を開始します](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002787.html)」
- 日立市「[ひたちBRTが本格運行！（平成31年4月から）](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002786.html)」
- 日立市「[新交通導入計画を策定しました](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html)」
- 国土交通省「[主な公的土地評価一覧](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000042.html)」
- 日立市「[大甕駅周辺地区整備計画](https://www.city.hitachi.lg.jp/machizukuri_kankyo/toshikyotenseibi/1009099/1002784.html)」

### R実装

- [`did` package official vignette](https://cran.r-universe.dev/did/doc/did-basics.html)
- [`did::att_gt` source and documentation](https://github.com/bcallaway11/did/blob/master/R/att_gt.R)
- [`did::aggte` documentation](https://www.rdocumentation.org/packages/did/versions/2.5.0/topics/aggte)
- [`fixest::sunab` documentation](https://rdrr.io/cran/fixest/man/sunab.html)
- [`fixest::vcov_conley` documentation](https://lrberge.github.io/fixest/reference/vcov_conley.html)
- [`HonestDiD` package](https://asheshrambachan.r-universe.dev/HonestDiD)
