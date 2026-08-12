# ひたちBRT第I期：固定地点イベントスタディDIDの詳細調査

> **位置づけ：参考資料・適用可能性未検証**
> この文書は分析手法の参考調査である。ひたちBRTの実データについて、年度別標本数、継続地点、対照候補、空間配置などを十分に確認する前に作成された。本文中の「推奨」「主分析」「適性」などの評価は現在の研究方針では確定事項ではなく、手法候補の採否は未評価である。現在の位置づけは [`docs/method_candidates.md`](../method_candidates.md) と有効な[意思決定ログ](../decision_logs/README.md)を正本とする。

調査日: 2026-08-12
対象: 候補1（地価公示を主データ、都道府県地価調査を独立した別サンプルとする固定地点イベントスタディDID）

## 結論

この方法は、**同じ標準地を毎年比較するため、売買された物件の構成変化を受けにくい、透明性の高い基準分析**になる。しかし、ひたちBRT第I期では、2013年の日立市地価公示56地点のうち当初停留所から800m以内が4地点、1.5km以内でも7地点しかない。さらに地点の選定替え、空間相関、2011年の計画公表・東日本大震災、第II期、2016年の停留所追加を扱う必要がある。したがって、**単独の主たる因果分析には弱く、主分析を支える固定地点ベンチマーク（副分析）としての適性が高い**。少なくとも中間発表では、点推定を「効果の確定値」とせず、処置地点数、係数経路、複数の不確実性評価、leave-one-outを同時に示すべきである。

最も防御可能な基本仕様は、次のとおりである。

- 結果変数: 1m²当たり地価の対数
- 処置: 第I期当初11停留所への事前固定した距離（暫定主仕様800m、1.5km等は感度分析）
- 地価公示の最後の事前観測: 2013年1月1日
- 地価公示の最初の事後観測: 2014年1月1日
- 地価調査の最後の事前観測: 2012年7月1日
- 地価調査の最初の事後観測: 2013年7月1日
- 主な推定窓: 2008--2017年（2018年3月の第II期先行運行より前で打ち切る）
- 比較群: 第I期停留所から十分離れ、用途・JRアクセス・海岸／災害リスク・事前価格水準と事前変化が比較可能な地点
- 報告: event-time別ATT、同時信頼帯、事前係数、HonestDiD感度、距離・対照・期間・地点継続条件の感度、処置地点leave-one-out

## 1. データの意味と日付

地価公示は、国土交通省土地鑑定委員会が標準地を選び、毎年1月1日時点の「正常な価格」を1m²当たりで判定する制度である。価格は建物等がないものとした更地価格であり、実際の取引価格そのものではない。標準地は毎年点検され、要件を欠く場合には選定替えが行われるため、地点コードを機械的につなぐだけでは固定地点パネルにならない（[国土交通省「地価公示制度の概要」](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000132.html)）。国土数値情報L01は位置、価格、利用現況、用途地域、地積等をGISデータで提供し、現行仕様には選定状況（継続、名称変更、削除、新設・選定替え等）もある（[国土数値情報・地価公示データ](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L01-2026.html)、[L01製品仕様書第3.2版](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L01-v3_2.pdf)）。

都道府県地価調査は、都道府県知事が基準地について毎年7月1日時点の正常価格を判定する制度である（[国土交通省「都道府県地価調査の実施状況」](https://www.mlit.go.jp/tochi_fudousan_kensetsugyo/tochi_fudousan_kensetsugyo_fr4_000001_00319.html)、[都道府県地価調査事業実施要領](https://www.mlit.go.jp/notice/noticedata/sgml/019/75000042/75000042.html)）。地価公示と地価調査は相互補完関係にあり一部は共通地点だが、基準日も地点集合も異なる（[不動産情報ライブラリ「地価公示・地価調査」](https://www.reinfolib.mlit.go.jp/landPrices/)）。したがって両者を一つの年次パネルに混ぜず、別々に推定する。

日立市資料では第I期は2013年3月に日立おさかなセンター--JR大甕駅東口間で開業しており（[日立市「ひたちBRTが本格運行」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002786.html)）、リポジトリ内の停留所調査は公式広報に基づき旅客取扱開始日を2013年3月25日、当初11停留所としている（[`docs/hitachi_brt_stop_openings_research.md`](../hitachi_brt_stop_openings_research.md)）。この日付と各地価の基準日から、イベント時点は次のように定義する。

| データ | 最後の事前観測 | 最初の事後観測 | 推定上の処置開始年 `g` | 基準イベント年 |
|---|---:|---:|---:|---:|
| 地価公示 | 2013-01-01 | 2014-01-01 | 2014 | 2013を `k=-1` |
| 都道府県地価調査 | 2012-07-01 | 2013-07-01 | 2013 | 2012を `k=-1` |

「地価公示2013年」を事後と扱うのは時間順序に反する。一方、地価調査2013年は開業約3か月後の最初の事後観測であり、開業直後の短期効果を表す。

## 2. 因果量（estimand）と式

地点を `i`、年を `t`、処置開始観測年を `g` とする。`D_i=1` は、第I期当初11停留所のいずれかから事前固定した距離 `r` 以内にある固定地点である。結果変数は `Y_it = log(円/m²)` とする。対象とする因果量は、基準年に存在し、指定した継続観測条件を満たす処置地点についてのイベント時点別平均処置効果である。

\[
ATT_k = E\left[Y_{i,g+k}(1)-Y_{i,g+k}(0)\mid D_i=1,\ i\in S\right],
\]

ここで `S` は、例えば2008--2017年に継続して同一画地として観測できる地点集合である。推定式は次の共通処置時点イベントスタディである。

\[
Y_{it}=\alpha_i+\lambda_t+
\sum_{k\neq -1}\beta_k
\{D_i\times 1(t-g=k)\}+\varepsilon_{it}.
\]

`α_i` は地点固定効果、`λ_t` は年固定効果、`k=-1` を省略基準とする。対数係数は小さい場合に概ね百分率変化で、厳密には `100(exp(β_k)-1)` % と解釈する。識別に必要なのは、少なくとも、(a) 処置がなければ処置・比較地点の平均地価変化が平行だった、(b) 開業前に効果がない、(c) 比較地点がBRTの波及効果を受けない、(d) 地点の残存・選定替えが処置効果と系統的に結び付かない、という仮定である。標準的DiDが平行トレンド下でATTを識別することは、Callaway and Sant'Annaの原論文の標準2群2期の説明と整合する（[Callaway & Sant'Anna 2021](https://www.sciencedirect.com/science/article/abs/pii/S0304407620303948)）。

全処置地点の開始時点が同じなら、処置時期がずれる場合にTWFEのlead/lagが他期の効果で汚染されるというSun and Abrahamの主要問題は生じない。ただし、将来、第II期や2016年追加停留所を同じ回帰に「段階処置」として入れる場合は別で、単純TWFEを使わずコホート別推定が必要になる（[Sun & Abraham 2021](https://www.sciencedirect.com/science/article/pii/S030440762030378X)）。この候補1では当初11停留所・2013年開業に固定し、第II期前で主窓を打ち切る。

## 3. 処置群、比較群、分析窓

### 3.1 処置群

処置地点は、**2013年3月25日に開業した当初11停留所**の最寄り地点までの距離で決める。2016年追加の「日立商業高校」を主処置定義に遡及して入れず、2019年にBRT停車を終えた当初停留所も2013年の処置集合には残す。これにより、結果を見た後の処置定義変更を防ぐ。

距離の事前提案は次のとおりである。

- 暫定主仕様: 800m以内
- 感度分析: 500m、1,000m、1,500m
- 可能なら道路ネットワーク徒歩距離、当面は再現可能な直線距離
- 800m仕様では800--1,500mを波及の可能性がある「donut」として比較群から除外する仕様も併記

800mを採用しても「正しい徒歩圏」と断定してはならない。閾値は結果を見る前に固定し、全距離仕様を同じ図表で公開する。2013年の既知集計は800m以内4地点、1.5km以内7地点であり、1.5kmを採用しても処置地点は非常に少ない。

### 3.2 比較群

第一候補は日立市内の非沿線固定地点である。同一市内なので市全体の景気・行政ショックを年固定効果で共有しやすいが、次の条件を事前情報だけで確認する。

- 住宅地／商業地等の用途が処置地点と重なる
- JR駅までの距離、幹線道路、海岸距離、標高、津波・洪水リスクが比較可能
- 2008--2010年等、計画・震災前の価格水準と変化が大きく外れない
- 第II期沿線や大甕駅再整備など、別の局所施策を直接受ける地点を識別できる
- 第I期停留所から十分離れ、BRTの地価波及を比較群に混ぜない

比較地点を事後の価格経路に最も合うよう選ぶと推定後選択になる。マッチングや層別化を行う場合も、処置前属性と事前結果だけで規則を固定する。日立市外の県北類似地点を追加する拡張仕様は比較群数を増やすが、市固有トレンドが混ざるため主仕様とはしない。

### 3.3 分析窓と予期効果

主窓は2008--2017年を提案する。2018年3月26日には第II期先行運行が始まるため、それ以後は第I期のみの効果ではなくなる（[日立市「常陸多賀駅まで運行開始」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002787.html)）。一方、BRTは2011年1月策定の新交通導入計画に基づいて導入されたため、2013年開業に対する「予期なし」は強い仮定である（[日立市地域公共交通網形成計画](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/002/851/moukeikakukaitei.pdf)）。2011--2013年のleadは単なる診断ではなく、計画・工事の資本化を含む可能性がある。

加えて、2011年の東日本大震災では日立市が震度6強等を観測し、津波浸水も生じた（[日立市地域防災計画・津波対策計画編](https://www-source.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/004/798/tsu01.pdf)）。沿線が沿岸側に偏るなら、復旧や災害リスク再評価がBRT効果と混ざり得る。したがって、海岸距離・実績浸水域による層別、沿岸同士の比較、2011年前後係数の明示を必須にする。

## 4. 必要データと固定地点パネルの作り方

### 4.1 必須列

各地価データについて、少なくとも次を保持する。

- データ種別（地価公示／地価調査）、年、基準日
- 原典の標準地・基準地番号、住所、緯度経度
- 価格（円/m²）と対数価格
- 選定状況、前年からの属性変更情報
- 用途区分、利用現況、周辺利用、用途地域、建蔽率・容積率
- 地積、形状、接面道路、最寄駅、駅距離
- 第I期当初停留所までの最短直線距離、可能なら徒歩距離
- 海岸距離、標高、津波浸水、JR駅距離等の事前地理属性

国土数値情報のL01仕様は価格に加えて地積、利用現況、用途地域等を持つ（[L01製品仕様書](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L01-v3_2.pdf)）。都道府県地価調査L02も公式製品仕様に従って属性を解釈する（[L02製品仕様書](https://nlftp.mlit.go.jp/ksj/jpgis/product_spec/KS-PS-L02-v1_1.pdf)）。年度により符号・属性名・測地系が変わり得るので、年度横断の変換表をコードとデータ辞書に残す。

### 4.2 地点継続の判定

地点固定効果は「同じ場所」を比較する設計なので、番号だけでなく次の順でcrosswalkを作る。

1. 公式番号と選定状況で継続候補を作る。
2. 住所、座標、地積、用途、接面道路を前年と照合する。
3. 座標の微小補正と実質的な画地変更を分ける。
4. 新設・選定替えは新しい `point_panel_id` とし、旧地点へ橋渡ししない。
5. 判定が曖昧な接続はフラグを立て、厳格パネルから外す。

公式には標準地が毎年点検され、適格性を欠くと選定替えされるため（[地価公示制度の概要](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000132.html)）、次の3標本を必ず比較する。

- **厳格balanced panel**: 主窓の全年度で同一画地として継続
- **unbalanced固定地点panel**: 同一性が確認できる観測期間のみ保持
- **全地点repeat cross-section**: 地点固定効果ではなく属性調整を用いる記述的感度分析

処置・比較群別に、毎年の継続数、新設数、削除数、選定替え率を表にする。処置後に沿線の選定替えが増えた場合、balanced panelの対象自体が選択されるため、固定地点ATTの外的妥当性が狭くなる。

## 5. 小標本、空間相関、事前トレンドへの対処

### 5.1 小標本

問題は総地点56よりも、処置地点が4または7しかないことである。通常のクラスタ頑健推論はクラスタ数が大きい漸近に依存し、少数クラスタでは過剰棄却し得る（[Cameron, Gelbach & Miller 2008](https://www.nber.org/papers/t0344)）。さらに少数処置群のDiDでは、対照群が多くても通常推論が信頼できない場合があり、Ferman and Pintoは少数処置群・異分散向け手法を提案している（[Ferman & Pinto 2019](https://direct.mit.edu/rest/article-pdf/101/3/452/1916793/rest_a_00759.pdf)）。

本件で取るべき措置は以下である。

- p値一つで結論を決めず、全係数、信頼区間、処置地点数を示す。
- 4地点それぞれを1つずつ除くleave-one-treated-point-outを必須とする。
- 処置地点別の生の価格系列と、処置群平均・比較群平均を図示する。
- post係数を年別に細分し過ぎず、0--1年、2--4年等の事前指定したbin平均も示す。
- wild cluster bootstrapは感度分析に使えるが、経済的に意味のある独立クラスタが少ないなら万能ではない。
- 偽路線・偽停留所の空間placebo分布を作り、推定値が空間的な偶然に対してどの程度極端か示す。ただしBRT配置がランダムではないため、これは厳密なランダム化検定とは呼ばない。

### 5.2 空間相関

近接地価は共通の地区ショックを受けるため、地点ごとの独立誤差は不自然である。Conleyは距離に応じた断面依存を許す非パラメトリック共分散推定を提示した（[Conley 1999](https://www.sciencedirect.com/science/article/pii/S0304407698000840)）。一方、少数処置単位と空間相関が併存するDiDでは独立クラスタを仮定した推論が歪み得る（[Alvarez & Ferman, “Inference in DID with Few Treated Units and Spatial Correlation”](https://arxiv.org/abs/2006.16997)）。

よって、次を並記する。

1. 地点クラスタSE（同一地点の系列相関）
2. 地理的な地区／メッシュクラスタSE（自然な区切りが妥当な場合のみ）
3. Conley空間HAC（例: 1km、2km、5kmのcutoff）
4. 空間placebo分布

地点数が少ないため、Conley cutoffをデータに都合よく選ばず全仕様を示す。4者の結果が大きく異なる場合は「推論が不安定」と結論する。

### 5.3 事前トレンド

lead係数とその同時信頼帯、処置前係数の共同検定は示すが、「有意でないから平行トレンドが成立」とは言わない。Rothは通常の事前トレンド検定の検出力が低く、検定合格後だけ推定を採用すると推定・区間を歪め得ることを示す（[Roth 2022](https://www.aeaweb.org/articles?id=10.1257%2Faeri.20210236)）。

代わりに、Rambachan and Rothの枠組みで、事後の平行トレンド違反が事前の差の何倍までなら結論が残るかを示す。この方法は厳密な平行トレンドを緩めた部分識別と一様妥当な推論を与える（[Rambachan & Roth 2023](https://academic.oup.com/restud/article-abstract/90/5/2555/7039335)）。ただし元の係数共分散推定が少数処置で不安定なら、HonestDiDもその問題を消さない。

## 6. R実装候補

| 役割 | パッケージ | 選定理由 | 注意 |
|---|---|---|---|
| 主回帰 | `fixest` | `feols()`で地点・年固定効果、event dummy、クラスタ・Conley等のVCOVを同じ枠組みで推定できる（[`feols`公式資料](https://lrberge.github.io/fixest/reference/feols.html)、[`vcov.fixest`](https://search.r-project.org/CRAN/refmans/fixest/html/vcov.fixest.html)） | 小標本の妥当性はパッケージが保証しない |
| 推定の照合 | `did` | `att_gt()`がgroup-time ATT、`aggte(type="dynamic")`が動学集約と同時帯を実装する（[`did` CRAN manual](https://mirror.opensource.iu.edu/cran/web/packages/did/did.pdf)） | 単一コホートでは`fixest`との差は小さい。少数処置問題は残る |
| 平行トレンド感度 | `HonestDiD` | Rambachan--Roth法の頑健区間を実装し、`did`の`AGGTEobj`も入力できる（[`HonestDiD` CRAN manual](https://stat.ethz.ch/CRAN/web/packages/HonestDiD/HonestDiD.pdf)） | 元推定の共分散に依存 |
| wild bootstrap | `fwildclusterboot` | `boottest()`でwild cluster bootstrapを実装する（[公式reference](https://s3alfisc.github.io/fwildclusterboot/reference/index.html)） | クラスタの意味と数が乏しい場合は補助的 |
| 空間処理 | `sf` | 停留所・地価点のCRS統一、距離、buffer、空間結合 | 投影座標で距離を計算し、CRSを記録する |

主回帰の概形は次である。

```r
library(fixest)

# g = 2014 for Land Price Publication; controls share calendar event time
panel[, event_time := year - 2014L]

m_es <- feols(
  log(price_yen_m2) ~ i(event_time, treated_800m, ref = -1) |
    point_panel_id + year,
  data = panel[year >= 2008 & year <= 2017],
  vcov = ~ point_panel_id
)

# Conley sensitivity: exact syntax/cutoff unit must be checked against the
# installed fixest version and coordinate fields.
m_conley <- summary(
  m_es,
  vcov = conley(2, distance = "spherical") ~ latitude + longitude
)
```

`did`による照合では、地価公示なら処置地点の`gname=2014`、never-treatedの比較地点は`gname=0`とする。

```r
library(did)

att <- att_gt(
  yname = "log_price",
  tname = "year",
  idname = "point_panel_id",
  gname = "first_treat_year", # 2014 treated, 0 controls
  data = balanced_panel,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = TRUE,
  cband = TRUE
)
dyn <- aggte(att, type = "dynamic")
```

## 7. 必須の診断、placebo、感度分析

### 7.1 データ診断

- 年×距離帯×用途別の地点数と継続率
- 処置・比較地点の地図、停留所、JR、海岸、浸水域
- 地点別価格系列と属性変更履歴
- 事前価格水準・変化、用途、駅距離等のbalance表
- 地価公示と地価調査の共通／近接地点一覧（推定は分離）

### 7.2 識別診断

- 全lead/lagと同時信頼帯
- 処置前係数の共同検定（不採択を仮定の証明にしない）
- 2011年計画・震災の前後に差が出るか
- 対照群で第II期や別再開発の影響が疑われる地点の監査
- 処置地点ごとの寄与とleave-one-out

### 7.3 Placebo

- 事前期間だけを使った偽開業年（複数年を同じ規則で実行）
- 同じ停留所数・路線長・都市用途構成を近似した偽停留所／偽路線
- 比較地域を処置とみなすin-space placebo
- 期待される影響範囲外（例: 5km超）で同じイベントパターンが出ないか

placeboは、結果を見て都合のよい偽年・偽路線だけを選ばず、生成規則と全結果を保存する。配置の無作為性が根拠づけられない限り、placebo順位は記述的な異常度であって厳密なp値ではない。

### 7.4 感度分析

- 距離: 500m、800m、1km、1.5km
- 距離法: 直線／道路ネットワーク
- donut: なし、0.8--1.5km除外、1--2km除外
- 対照: 日立市内全非沿線、用途一致、沿岸一致、市外県北追加
- 期間: 2005--2017、2008--2017、2010--2017（後者は震災と計画のため特に慎重）
- 結果変数: `log(price)`、水準、対前年変化率
- 地点集合: balanced、unbalanced、選定替え除外
- 公示／地価調査の独立再推定
- 2016年追加停留所に新たに近接する地点を2016年以後除外／別処置として扱う
- 推論: 地点cluster、地区cluster、Conley cutoff、wild bootstrap、空間placebo
- HonestDiD: 相対偏差上限 `Mbar` の一連の値

結果変数の対数と水準で結論が変わる可能性は単なる技術問題ではなく、平行トレンド仮定自体が関数形に依存し得るため、両方を示す意味がある（[Roth & Sant'Anna 2023](https://onlinelibrary.wiley.com/doi/abs/10.3982/ECTA19402)）。

## 8. ひたちBRTでの実現可能性と位置づけ

### 実現可能な点

- 年次の公的価格と位置・画地属性が長期で利用可能である。
- 第I期当初停留所と開業日が一次資料から復元されている。
- 地価公示は2013年を明確な最後の事前観測にできる。
- 同一地点比較により、取引物件の構成変化を大きく避けられる。
- 地価調査を異なる地点集合・基準日で独立再推定できる。

### 決定的な弱点

- 2013年の日立市地価公示56地点中、処置は800m以内4地点、1.5km以内7地点しかなく、継続地点に絞るとさらに減り得る。
- 地価点と処置が空間的にまとまり、独立クラスタという推論仮定が弱い。
- 2011年の計画公表、工事期待、同年の震災・復旧が開業前係数と処置効果を混ぜ得る。
- 近い比較地点はBRT波及、遠い比較地点は構造差というtrade-offがある。
- 標準地の選定替えは処置後の標本選択を生み得る。
- 2016年停留所追加、2018年以降の第II期により長期効果の解釈が変わる。

### 判定

| 用途 | 適性 | 理由 |
|---|---|---|
| 単独の主分析 | 低--中 | 処置地点が4--7、空間相関・予期・震災に対して確定的推論が難しい |
| 固定地点ベンチマーク | 高 | 透明で再現可能、取引構成変化が小さい |
| 地価調査による別サンプル確認 | 中 | 地点集合と基準日が異なるが、こちらも処置地点が少ない |
| 中間発表の予備推定 | 高 | 設計、データ監査、係数経路、限界を明瞭に示せる |

したがって、本手法は**「主分析の結論を支える固定地点のアンカー」**と位置づけるのが妥当である。不動産取引価格等で観測数を増やす分析が別に成立した場合、その結果が固定地点パネルでも方向・時期・距離勾配について整合するかを確認する役割を持たせる。

## 9. 具体的な実装順序

1. **分析計画を固定**: 第I期当初11停留所、800m暫定主仕様、全感度仕様、2008--2017年、結果変数、除外規則を文書化する。
2. **年度仕様を正規化**: L01/L02の年度別フィールド、測地系、欠損・符号をデータ辞書へ写す。
3. **地点crosswalkを作る**: 番号、選定状況、住所、座標、地積、用途、道路を照合して`point_panel_id`を付ける。曖昧接続を人手確認する。
4. **停留所処置を固定**: 2013年当初11停留所だけのgeometryを作り、各年地点へ最短距離を付与する。距離は基準年の固定座標を使い、地点移動を処置変化と誤認しない。
5. **競合要因を付ける**: JR距離、海岸距離、標高、浸水、用途、道路等を付与し、処置前値を固定する。
6. **分析標本フローを出す**: 56地点から距離、用途、継続条件、欠損で何地点になったかを群別に表示する。
7. **記述図を先に作る**: 地図、地点別系列、群平均、事前balance、選定替え。
8. **地価公示を推定**: `fixest`で共通時点event studyを推定し、地点cluster・Conley等を併記する。post bin平均も推定する。
9. **頑健性を機械実行**: 距離、donut、対照、窓、パネル条件をgrid化し、全仕様を保存する。
10. **小標本診断**: 4地点leave-one-out、wild bootstrap、空間placeboを実行する。
11. **平行トレンド感度**: 同時帯、共同検定、`HonestDiD`の`Mbar`系列を出す。
12. **地価調査を別パイプラインで再推定**: `g=2013`に変え、地価公示との共通地点重複を明記する。
13. **結果の格付け**: 方向、時期、距離、データ種別、標本、推論法で一致するかを表にし、「頑健／示唆的／不安定」を事前規則で判定する。

## 主要一次資料

- 国土交通省「[地価公示制度の概要](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000132.html)」
- 国土交通省「[国土数値情報・地価公示データ](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L01-2026.html)」および「[L01製品仕様書](https://nlftp.mlit.go.jp/ksj/gml/product_spec/KS-PS-L01-v3_2.pdf)」
- 国土交通省「[都道府県地価調査](https://www.mlit.go.jp/tochi_fudousan_kensetsugyo/tochi_fudousan_kensetsugyo_fr4_000001_00319.html)」および「[L02製品仕様書](https://nlftp.mlit.go.jp/ksj/jpgis/product_spec/KS-PS-L02-v1_1.pdf)」
- 日立市「[ひたちBRTが本格運行](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002786.html)」
- 日立市「[ひたちBRTが常陸多賀駅まで運行を開始](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002787.html)」
- Callaway, B. and Sant'Anna, P. H. C. (2021), “[Difference-in-Differences with Multiple Time Periods](https://www.sciencedirect.com/science/article/abs/pii/S0304407620303948).”
- Sun, L. and Abraham, S. (2021), “[Estimating Dynamic Treatment Effects in Event Studies with Heterogeneous Treatment Effects](https://www.sciencedirect.com/science/article/pii/S030440762030378X).”
- Ferman, B. and Pinto, C. (2019), “[Inference in Differences-in-Differences with Few Treated Groups and Heteroskedasticity](https://direct.mit.edu/rest/article-pdf/101/3/452/1916793/rest_a_00759.pdf).”
- Conley, T. G. (1999), “[GMM Estimation with Cross Sectional Dependence](https://www.sciencedirect.com/science/article/pii/S0304407698000840).”
- Roth, J. (2022), “[Pretest with Caution](https://www.aeaweb.org/articles?id=10.1257%2Faeri.20210236).”
- Rambachan, A. and Roth, J. (2023), “[A More Credible Approach to Parallel Trends](https://academic.oup.com/restud/article-abstract/90/5/2555/7039335).”
