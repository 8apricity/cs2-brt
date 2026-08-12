# ひたちBRT第I期：不動産取引価格情報を用いる距離勾配型DIDの詳細調査

> **位置づけ：参考資料・適用可能性未検証**
> この文書は分析手法の参考調査である。ひたちBRTの実データについて、年度別標本数、継続地点、対照候補、空間配置などを十分に確認する前に作成された。本文中の「推奨」「主分析」「適性」などの評価は現在の研究方針では確定事項ではなく、手法候補の採否は未評価である。現在の位置づけは [`docs/method_candidates.md`](../method_candidates.md) と有効な[意思決定ログ](../decision_logs/README.md)を正本とする。

調査日: 2026-08-12
対象: 候補5（不動産取引価格情報を中心とする距離帯・連続距離・空間イベントスタディ）

## 結論

距離勾配型DIDは、**BRTの便益がどの範囲まで届くか、停留所直近では騒音・交通等の負の外部性が便益を相殺するか**を調べられる点で、単純な「800m以内×開業後」のヘドニックDIDより研究上の追加価値が大きい。査読研究でも、近接処置と少し遠い対照を比べる ring method や、距離に沿う処置効果曲線を推定する方法が整理されている（[Butts 2023](https://doi.org/10.1016/j.jue.2022.103493)）。

しかし、**国土交通省が一般公開する不動産取引価格情報だけでは、個々の物件からBRT停留所までの連続距離を作れない**。公式制度が公表する所在地は町・大字レベルであり（[国土交通省「不動産取引価格情報提供制度」](https://www.mlit.go.jp/totikensangyo/totikensangyo_tk5_000069.html)）、価格情報取得API `XIT001`にも緯度・経度または地番はなく、`DistrictName`（地区名）だけがある（[XIT001公式仕様](https://www.reinfolib.mlit.go.jp/help/apiManual/xit001/)）。さらに、地図用のポイントAPI `XPT001` が返す点は**対象不動産ではなく最寄り駅の点**であり、同じ点に複数取引が入ると公式仕様が明記する（[XPT001公式仕様](https://www.reinfolib.mlit.go.jp/help/apiManual/xpt001/)）。この点を物件座標として使うことはできない。

したがって、本候補についての判定は次のとおりである。

| データ条件 | 防御可能性 | 推奨する扱い |
|---|---|---|
| 公開取引価格情報だけ | 低 | 250m・500m等のring、連続距離、スプラインを主分析にしない |
| 町・大字ポリゴンを付与 | 低～中 | ポリゴン全域が同じ広い距離帯に入る「明確な地区」だけの粗い分類・記述分析 |
| 正確な物件座標を別途適法に取得 | 中～高 | 距離帯イベントスタディを実施可能。連続曲線は十分な件数を確認後に補助分析 |
| 正確な位置を持つ地価公示・地価調査 | 位置は高、標本数は低 | 候補1の感度・メカニズム確認。取引データの観測数増加という利点は失う |

**中間発表では、不動産取引価格情報による距離勾配型DIDを主分析に置かない。** まず公開データで日立市・周辺市町村の取引件数と地区粒度を監査し、候補4の粗いヘドニックDIDが成立するかを確認する。候補5は、(a) 地区ポリゴンによる誤分類に強い幅広い帯の探索分析、または (b) 将来、正確な物件位置を得られた場合の拡張分析、と位置づけるのが誠実である。町・大字代表点から算出した「小数点付きの距離」を真の物件距離のように扱ってはならない。

## 1. この方法が答える問いと因果量

### 1.1 距離帯（ring）別の静学的効果

取引 `j`、取引四半期 `t`、第I期停留所までの開業前に固定した距離 `d_j` を考える。距離帯を例えば `b = {0--250m, 250--500m, 500--800m, 800--1,500m}` とし、十分遠い非曝露地域を基準群にする。候補estimandは、各帯にある取引対象についての開業後の平均価格効果である。

\[
ATT_b = E[Y_{jt}(1)-Y_{jt}(0)\mid d_j\in b,\ t\ge T_0].
\]

反復横断面のヘドニックDIDは次で表せる。

\[
\log P_{jt}=\alpha_{a(j)}+\lambda_t+X_{jt}'\gamma
+\sum_{b\ne b_0}\beta_b\{1(d_j\in b)\times Post_t\}+\varepsilon_{jt}.
\]

`P`は土地取引なら円/m²、土地建物なら総額または適切な価格指標、`X`は面積、形状、前面道路、用途地域、建物面積、築年、構造等、`α`は処置前に定めた小地域固定効果、`λ`は四半期固定効果である。`β_b`は単なる開業後の距離別価格差ではなく、**同じ距離帯と基準地域の価格差が開業前後でどれだけ変わったか**を表す。

### 1.2 距離帯×イベント時点

開業前トレンド、予期、効果の立ち上がりを調べる主仕様は次である。

\[
\log P_{jt}=\alpha_{a(j)}+\lambda_t+X_{jt}'\gamma
+\sum_b\sum_{k\ne -1}\beta_{bk}
1(d_j\in b)1(t-T_0=k)+\varepsilon_{jt}.
\]

四半期ごとではセルが小さくなりやすいため、実データの件数を見て、事前に次のようなbinを固定する。

- 2008--2010年: 計画・震災より前の基準期間
- 2011--2012年: 計画公表、震災、工事・期待を含む予期期間
- 2013年第1四半期: 開業日が3月25日のため「開業四半期」として独立表示
- 2013年第2四半期--2014年: 初期事後
- 2015--2017年: 第II期先行運行前の中期事後

`2013Q1`を丸ごと事後にすると、四半期のほぼ全期間を開業前として扱う誤分類になる。主仕様では移行期として除外または独立係数にし、完全な最初の事後四半期を`2013Q2`とする。ただし、BRT計画は2011年1月以前から検討され、日立市は2009年3月の跡地活用基本構想を経て新交通導入計画を策定している（[日立市「新交通導入計画を策定しました」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html)）。したがって「開業まで効果ゼロ」という無予期仮定は強く、2011--2012年の係数をBRT効果が存在しない純粋なplaceboとは呼べない。

### 1.3 連続距離効果

正確な物件座標がある場合の候補は、開業前後の価格距離曲線の差である。

\[
\tau(d)=E[\log P(1)-\log P(0)\mid D=d].
\]

推定候補は次の3つである。

1. **線形または区分線形**: `Post × d`、250m・500m・800m等にknotを置く。
2. **制限付きスプライン**: `Post × spline(d)`。形を柔軟にするが、自由度・knotを結果に合わせない。
3. **partitioning/bin推定**: 距離をデータ駆動のbinに分け、点ごとの区間と一様信頼帯を付ける。Buttsは、真の影響範囲を既知と仮定する単一ringより、距離に応じた処置効果曲線を推定する利点を示す（[Butts 2023](https://www.sciencedirect.com/science/article/pii/S0094119022000705)）。`binsreg`はpartitioning-based least squares、点ごとの信頼区間、一様信頼帯、bin数選択を実装する（[`binsreg`公式R資料](https://search.r-project.org/CRAN/refmans/binsreg/html/binsreg.html)）。

ただし、連続距離は「観測数が多いから自動的に優れる」わけではない。距離の位置誤差、非線形形状、遠方での対照の非比較性に敏感である。**公開取引データの位置粒度ではこのestimandを識別できない**。

## 2. アクセシビリティ便益と停留所直近の負の外部性

BRT開業は少なくとも二つの逆方向の経路を持つ。

- **停留所アクセシビリティ**: 停留所までの歩行負担、移動時間、不確実性が下がることで、近い土地の支払意思額が上がる。
- **局所的なdisamenity**: バス走行・発着による騒音、振動、排気、ヘッドライト、歩行者・車両集中、プライバシー、専用路・幹線道路への近接が価格を下げ得る。

鉄道研究では、駅距離をアクセシビリティ、線路距離をnuisanceの代理として分ける設計が使われている（[Chen, Rufolo & Dueker 1998](https://doi.org/10.3141/1617-05)）。Ahlfeldtらは、駅への近さの正の便益と鉄道騒音の負の効果を同時に条件づけないと、双方の効果を過小評価し得ることを示している（[Ahlfeldt, Nitsch & Wendland 2016](https://www.ifo.de/DocDL/cesifo1_wp6058.pdf)）。BRTについても、北京では停留所への近さと正の価格関連を報告する研究がある一方（[Deng et al. 2016](https://doi.org/10.1016/j.retrec.2016.08.005)）、BRT1では5--10分徒歩圏が直近・遠方より高いという非単調な結果がある（[Zhang & Wang 2015](https://doi.org/10.5038/2375-0901.18.2.3)）。これは他都市の係数を日立へ移植できるという意味ではなく、**「近いほど常に高い」という単調制約を置くべきでない**根拠になる。

ひたちBRTでは次を分ける必要がある。

- `distance_stop`: 2013年当初11停留所の最寄り点までの距離（便益側）
- `distance_guideway`: 第I期専用道路または走行区間までの距離（局所外部性側）
- 可能なら、停留所への道路ネットワーク徒歩距離
- 既存幹線道路、JR常磐線、旧日立電鉄線跡地への距離

例えば、`0--250m`で総効果が小さく、`250--800m`で正なら、「直近disamenityが便益を一部相殺」という解釈候補になる。ただし、停留所が商業中心や幹線道路沿いに選ばれる内生性、取引物件の構成、位置誤差でも同じ形は生じるため、ring形状だけでメカニズムを確定しない。

## 3. 処置・対照・イベント時点

### 3.1 処置geometry

主処置は、リポジトリで公式資料から復元済みの**2013年3月25日当初11停留所**に固定する（[`docs/hitachi_brt_stop_openings_research.md`](../hitachi_brt_stop_openings_research.md)）。

- 2016年追加の日立商業高校停留所を2013年に遡及させない。
- 2019年にBRT停車を終えた中沢・旧大甕駅前も2013年の処置集合には残す。
- 2018年第II期先行運行以後は第I期のみの効果でなくなるため、主窓を2017Q4までとする。
- 長期拡張では2016年追加・2018/2019年第II期を別処置としてモデル化する。

### 3.2 距離帯

正確な位置が得られた場合の事前候補は次である。

| 帯 | 主な解釈 | 留意点 |
|---|---|---|
| 0--250m | 強いアクセス＋強い局所外部性 | 位置誤差に最も弱い。件数不足なら独立推定しない |
| 250--500m | 近距離徒歩圏 | 直近との比較で非単調性を確認 |
| 500--800m | 広い徒歩圏 | 事前の主要便益帯候補 |
| 800--1,500m | 波及・donut候補 | 直ちに対照としない |
| 1,500--3,000m | 近隣対照候補 | 効果が残れば汚染される |
| 3,000m超 | 遠方対照候補 | 沿線との構造差が大きくなり得る |

境界は実データの結果を見る前に固定し、件数が不足する場合は`0--500m`、`500--1,000m`、`1--2km`のように粗くする。位置誤差が帯幅と同程度なら細分しない。

### 3.3 対照群

「800mのすぐ外」を対照にすれば地域特性は近いが、BRT効果が800mを超えて波及すると対照が汚染される。逆に遠い地点は非曝露になりやすいが、海岸・用途・JRアクセス・大甕駅圏との構造差が増える。空間spilloverがあると、標準DIDは対照群のspilloverを処置効果から差し引いてしまう（[Butts, “Difference-in-Differences Estimation with Spatial Spillovers”](https://www.kylebutts.com/files/Spillover.pdf)）。

対照の候補は次の順で監査する。

1. 日立市南部で第I期から十分離れ、第II期予定地でもない地区
2. 日立市内で用途、JR距離、海岸距離、津波リスク、事前価格水準・変化が近い地区
3. 東海村等の近隣自治体を加えた比較（自治体固有ショックを別途扱う）

主仕様では、推定した効果曲線が概ねゼロに戻る距離より外側を対照候補にする。ただし、結果を見て都合よく外径を選ぶと推定後選択になる。主外径と複数の感度外径を事前登録し、全結果を示す。

## 4. 公開取引データの位置粒度：厳格な評価

### 4.1 公式仕様から確定できること

不動産取引価格情報は、取引当事者へのアンケート回答等を、物件が容易に特定できないよう加工して公表する制度である（[不動産情報ライブラリ「制度と用語」](https://www.reinfolib.mlit.go.jp/realEstatePrices/about/)）。国土交通省が列挙する公開所在地は**町・大字レベル**で、取引価格も有効数字2桁である（[制度概要](https://www.mlit.go.jp/totikensangyo/totikensangyo_tk5_000069.html)）。

`XIT001`の主な位置関連フィールドは市区町村コード、地区名、地区コード、最寄駅名・距離等であり、緯度、経度、地番、街区、物件IDは公開出力にない。また、地区コード・地区名はデータ更新時に変わることがあり、過去との継続性を保証しない（[XIT001公式仕様](https://www.reinfolib.mlit.go.jp/help/apiManual/xit001/)）。取引時期は四半期であり、取引価格は2005年第3四半期以降利用できる（[API一覧](https://www.reinfolib.mlit.go.jp/help/apiManual)）。

最も危険な誤解は`XPT001`である。このAPIはGeoJSONの「ポイント」を返すが、公式説明は「対象となる不動産の最寄り駅のポイントを返却」すると明記する。そのため同一ポイントに複数価格情報が含まれる（[XPT001公式仕様](https://www.reinfolib.mlit.go.jp/help/apiManual/xpt001/)）。これは地図表示用の代表点であって、取引物件の点ではない。

### 4.2 なぜ町・大字代表点では連続距離を推定できないか

地区重心または町名をジオコードした代表点から停留所距離を計算しても、得られるのは`distance(地区代表点, 停留所)`であり、`distance(取引物件, 停留所)`ではない。同じ地区内の全取引が同じ擬似距離を持ち、停留所を含む細長い地区では真の距離が数十mから数kmまで広がり得る。

位置を秘匿・集計したときの距離誤差は、距離係数や推論を歪める。位置のgeo-maskingが距離を説明変数にするモデルへmeasurement errorを導入し、結論を歪め得ることは理論・シミュレーション研究でも示されている（[Arbia et al. 2015](https://doi.org/10.3390/econometrics3040709)）。一般に古典的誤差なら勾配がゼロ方向へ薄まることがあるが、本件では地区形状、停留所配置、海岸・幹線道路との関係により誤差が非古典的になり得る。単純な「過小評価だけ」と決めつけられない。

### 4.3 公開データで許容できる縮退案

公開データだけで行うなら、各地区ポリゴン `A` について次を計算する。

\[
d_{min}(A)=\min_{x\in A,s\in S}\|x-s\|,
\qquad
d_{max}(A)=\max_{x\in A}\min_{s\in S}\|x-s\|.
\]

- `d_max <= 800m`なら、その地区内の全地点が800m以内である「確実処置地区」
- `d_min >= 1,500m`なら、全地点が1.5km以上離れる「確実遠方地区」
- 境界をまたぐ地区は「位置不明」として主推定から除外

この方法は誤分類を減らすが、標本を大きく失い、estimandは物件距離効果でなく**地区レベル曝露効果**になる。町・大字境界の公式時系列crosswalkも必要であり、API自身が地区名・コードの継続性を保証しない点に注意する。

追加の感度として、地区内に一様、住宅地内に一様、建物メッシュに比例、という複数の位置分布を仮定して擬似地点を反復生成し、ring分類確率を付けるmultiple-imputation風の分析はできる。しかし真の分布仮定をデータから検証できないため、主たる因果推定にはしない。

## 5. 主要な脅威と対処

### 5.1 帯域・donut・spillover

- 内径・外径を結果に合わせない。主仕様と感度gridを事前固定する。
- 800--1,500m等をdonutとして対照から外す仕様を置く。
- 多数のringを一度に推定して効果がゼロへ戻る距離を可視化する。
- 遠方でも係数がゼロに戻らない場合、共通トレンド不成立または広域波及として、局所DIDを支持しない。
- 第II期予定地、2016年追加停留所、大甕駅再整備等の競合処置を地図で除外・別フラグ化する。

### 5.2 空間相関

近隣取引は同じ局所需要・供給ショックを共有する。通常のheteroskedasticity-robust SEだけでは不十分である。`fixest`は緯度経度と距離cutoffを指定するConley VCOVを実装する（[`vcov_conley`公式資料](https://lrberge.github.io/fixest/reference/vcov_conley.html)）。正確な座標がある場合、1km・2km・5km等の事前指定cutoffを併記する。

ただし、公開取引データには物件座標がないため、地区重心をConley計算に使っても「精密な空間推論」にはならない。また、小地域cluster数が少ない場合、cluster SEも不安定である。地点クラスタ、地区クラスタ、Conley、空間placeboが大きく異なるなら、不確実性が推論法に敏感と報告する。

### 5.3 多重比較・柔軟性

距離帯×イベント時点を多数推定すると偶然の有意係数が出やすい。

- 主要仮説を「0--800mの平均事後効果」または「0--500mと500--1,000mの共同効果」1--2個に限定
- 距離曲線には点ごとの区間だけでなく一様信頼帯
- ring係数の共同検定
- 全仕様・全距離帯を表示し、有意なものだけ選ばない
- placebo分布を用いる場合も偽地点生成規則を固定

### 5.4 反復横断面の構成変化

公示地価と違い、毎期同じ物件が売れるわけではない。BRT開業後に沿線で土地付き建物の比率、新築、面積、用途、道路条件が変われば、価格変化と取引構成変化が混ざる。公式も、価格は面積・前面道路・個別事情で異なり、丸め以外の補正を行わないと注意している（[制度と用語](https://www.reinfolib.mlit.go.jp/realEstatePrices/about/)）。

対処は次のとおりである。

- 宅地（土地）を主標本とし、円/m²を結果にする。
- 土地と建物、中古マンションは混ぜず、別モデルにする。
- 面積、形状、間口、道路方位・種類・幅員、用途地域、建蔽率・容積率を調整。
- 建物を扱う場合は延床面積、築年、構造、用途を調整。
- 距離帯×時期ごとに全属性の分布と欠損率を表示。
- 属性を結果とした同じDIDを行い、構成変化を直接診断。
- 共通support外の物件をtrimし、重み付け仕様を感度として比較。
- 取引件数自体を結果として表示。価格上昇と流動性変化を混同しない。

アンケートベースであるため回答選択もある。国土交通省の2021年資料では、2005年7月～2020年12月の累計アンケート回収率は33.5%である（[令和3年度土地鑑定委員会資料](https://www.mlit.go.jp/policy/shingikai/content/001402651.pdf)）。これは現在の日立市の回答率を示す値ではないが、公開取引が全登記取引の無作為標本だと仮定できないことを示す。年・地域・物件種別別の公開件数変化を必ず監査する。

### 5.5 東日本大震災

第I期沿線は沿岸南部にあり、2011年3月の震災・津波とBRT計画が近接する。日立市の防災計画は東日本大震災時の浸水面積4km²、全壊17件、大規模半壊148件等を示す（[日立市地域防災計画](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/007/914/1syou_r6.8.pdf)）。留町では避難経路の浸水等があり、後年の復興事業も実施された（[日立市復興交付金事業計画](https://www.city.hitachi.lg.jp/_res/projects/default_project/_page_/001/004/955/02.pdf)）。

震災は単なる全国年固定効果で消えない。被害・復旧・リスク再評価が沿岸で強いからである。

- 2011年実績浸水域、海岸距離、標高を付与
- 実績浸水地区を除外した仕様
- 沿岸同士・非浸水同士に限定した仕様
- 2008--2010年の震災前勾配、2011--2012年の震災・計画期、2013年以後を別表示
- BRT係数と同時に、震災後×浸水・海岸距離を入れる仕様
- 震災復興事業の位置・時期を監査

それでもBRT計画と復興の空間配置が重なる場合、統計的調整だけで分離できない。結果は「BRT第I期開業と同時期の沿線相対変化」と限定して解釈する。

## 6. R実装案

### 6.1 正確な物件座標がある場合

```r
library(sf)
library(data.table)
library(fixest)

# Metric CRS appropriate for Ibaraki; record the exact EPSG in the data dictionary.
sales_sf <- st_transform(sales_sf, target_crs)
stops_i  <- st_transform(stops_i, target_crs)
guideway <- st_transform(guideway, target_crs)

sales[, d_stop_m := apply(
  units::drop_units(st_distance(sales_sf, stops_i)), 1, min
)]
sales[, d_line_m := units::drop_units(
  st_distance(sales_sf, guideway, by_element = TRUE)
)]

sales[, ring := cut(
  d_stop_m,
  breaks = c(0, 250, 500, 800, 1500, 3000, Inf),
  right = FALSE
)]

# 2013Q1 is transition; complete post begins 2013Q2.
m_ring <- feols(
  log(unit_price_yen_m2) ~ i(event_bin, ring, ref = "pre_ref") +
    log(area_m2) + land_shape + road_type + road_width_m + zoning |
    small_area_id + quarter,
  data = sales[type == "宅地(土地)" & quarter != "2013Q1"],
  vcov = conley(2, distance = "spherical") ~ latitude + longitude
)
```

`sf::st_distance()`は地理座標ならgreat-circle、投影座標ならCRS単位のEuclidean距離を計算する（[`sf`公式資料](https://r-spatial.github.io/sf/reference/geos_measures.html)）。直線距離と徒歩ネットワーク距離は別列にし、どちらを主仕様とするか事前に決める。

イベント時点を細かくし過ぎない静学仕様は次である。

```r
sales[, post := quarter >= "2013Q2"]

m_post <- feols(
  log(unit_price_yen_m2) ~ i(ring, post, ref = "[3000,Inf)") +
    log(area_m2) + land_shape + road_type + road_width_m + zoning |
    small_area_id + quarter,
  data = sales[type == "宅地(土地)" & quarter != "2013Q1"],
  vcov = conley(2) ~ latitude + longitude
)
```

距離曲線は、まず属性・小地域・時間効果を除いた価格変化を作り、`binsreg`で開業後差を描く方法が候補になる。柔軟なスプラインは`mgcv`でも実装できるが、`mgcv`の既定smoothはthin plate regression splineで、basis dimensionが最大自由度を制約する（[`mgcv`公式資料](https://search.r-project.org/CRAN/refmans/mgcv/html/gam.models.html)）。研究者自由度を増やすため、スプラインは主推定でなく、事前に固定したring結果の補助図とする。

### 6.2 公開データだけの場合

```r
# district polygons must be historical/cross-walked; a centroid is not a parcel.
# Compute min/max possible stop distance for the polygon.
districts[, d_min_m := units::drop_units(
  apply(st_distance(st_boundary(geometry), stops_i), 1, min)
)]

# d_max requires adequate densification of polygon boundaries and interior
# checks; validate geometrically rather than treating this sketch as production code.

districts[, exposure_class := fifelse(
  d_max_m <= 800, "certain_within_800",
  fifelse(d_min_m >= 1500, "certain_beyond_1500", "ambiguous")
)]
```

公開データ仕様では、`ambiguous`を細かいringへ強制分類しない。地区重心距離を使う場合、列名を`district_centroid_distance`とし、図表にも「物件距離ではない」と明記する。

## 7. 必須の診断・placebo・感度分析

### 7.1 最初に行うfeasibility audit

- 年・四半期×物件種別×地区の取引件数
- 地区名・地区コードの年次変化、表記揺れ、境界crosswalk
- 各地区ポリゴンの`d_min`、`d_max`、幅、面積
- 「確実処置」「確実遠方」「曖昧」の件数
- ringを仮定した場合の各セル件数と属性欠損率
- 最寄駅点が同じ複数取引を地図上で確認し、物件点として使っていないことを検証
- 価格、面積、道路幅等の丸め・top coding・異常値

この監査で、開業前後それぞれの確実処置地区に十分な土地取引がない場合、公開取引価格による候補5は中止する。

### 7.2 事前トレンドと予期

- 2008--2010年の距離帯別価格推移
- 2011Q1計画・2011Q1震災以後の係数
- 2013Q1を除外／事前／移行期とする3仕様
- 開業前係数の共同検定と一様信頼帯
- 「有意でない」を平行トレンドの証明にしない
- 2009年基本構想を予期開始とする感度

### 7.3 Placebo

- 2008--2010年内の偽開業四半期
- 日立電鉄跡地上の未開業区間または同じ道路・沿岸条件を持つ偽停留所集合
- 同じ停留所数・沿線長・用途構成になる空間placebo
- 3km超等、想定外遠方での偽効果
- BRTの影響を受けにくい物件属性（例: 土地面積）を結果にしたplacebo/構成診断

空間placeboの位置はランダムに配置された政策ではないため、順位を厳密なrandomization p値と呼ばず、空間的な異常度の診断とする。

### 7.4 距離・位置誤差の感度

- 直線距離／道路ネットワーク距離
- 0--250--500--800m／0--500--1,000m／0--800mの粗い帯
- 外径1.5km、2km、3km、5km
- donutなし／800--1,500m除外／1--2km除外
- 停留所距離と専用路距離を同時に調整／別々に推定
- 地区全域分類のみ／重心分類／複数の地区内位置分布による確率分類
- 境界から100m、250m、500m以内の曖昧観測を除外
- exact geocode subsetが得られた場合、公開代理距離との誤差分布・誤分類率を直接検証

### 7.5 標本・仕様の感度

- 宅地（土地）のみを主仕様
- 土地建物・中古マンションを別推定
- 2007--2017、2008--2017、2009--2017等の期間
- 浸水域除外、沿岸限定、非浸水限定
- 日立市内対照、近隣自治体追加、用途・事前傾向の共通support限定
- 2016年追加停留所近傍を2016年以後除外
- 大甕駅周辺整備・第II期予定地を除外
- Conley cutoff、地区cluster、四半期cluster等の推論比較
- influential district / leave-one-district-out

## 8. 候補4「単純ヘドニックDID」との差と追加価値

| 観点 | 候補4：ヘドニックDID | 候補5：距離勾配型DID |
|---|---|---|
| 主処置 | 沿線内外の二値 | 複数ringまたは連続距離 |
| 主estimand | 指定圏内の平均効果 | 距離ごとの効果・影響範囲 |
| 直近外部性 | 平均に埋もれる | 直近と徒歩圏を分けて検出可能 |
| 閾値依存 | 1つの閾値に強く依存 | 複数帯・曲線で可視化できる |
| spillover | 対照汚染として扱う | spillover自体を距離別に推定し得る |
| 必要位置精度 | 地区単位の粗い処置なら実施余地あり | 原則として物件点または非常に小さい空間単位が必要 |
| 多重比較・自由度 | 比較的小さい | 大きい。一様帯・事前指定が必要 |
| ひたちBRT公開データでの実現性 | 地区曝露を慎重に定義すれば中 | 細かな距離勾配は低 |

追加価値は、平均効果がゼロでも「停留所直近の負」と「少し離れた徒歩圏の正」が相殺している可能性を発見できること、効果がどこでゼロへ戻るかを示して対照範囲を検証できることである。一方、その追加価値は正確な位置情報に依存する。**公開データで偽精度の連続距離を作るくらいなら、候補4の粗く透明な地区曝露DIDの方が防御可能**である。

## 9. ひたちBRTでの実現可能性と推奨役割

### 実現可能な点

- 取引データは2005年第3四半期以降、四半期単位であり、2013年3月25日の開業を年次地価より細かく扱える（[XIT001公式仕様](https://www.reinfolib.mlit.go.jp/help/apiManual/xit001/)）。
- 土地、土地建物、中古マンション等を分離でき、面積、道路、用途地域等のヘドニック属性がある。
- 第I期停留所・専用路geometryと開業履歴はリポジトリで整備されている。
- 正確な物件位置が得られれば、非単調な近接効果、効果範囲、spilloverを直接調べられる。

### 決定的な弱点

- 公開所在地は町・大字で、APIに物件座標がない。
- 地図ポイントは物件でなく最寄駅である。
- 地区名・コードの時系列継続性も保証されない。
- 反復横断面なので取引構成と回答選択が変化する。
- 震災・復興、2009/2011年からの計画期待、大甕駅周辺整備が空間・時間的に重なる。
- 距離帯×時点のセルを増やすほど小標本・多重比較になる。

### 判定

| 役割 | 適性 | 理由 |
|---|---|---|
| 公開取引データでの主分析 | 低 | 真の物件--停留所距離を観測できない |
| 公開取引データの粗い地区曝露DID | 中 | 候補4としては実施余地。距離勾配とは呼ばない方がよい |
| 公開データでの探索的ring分析 | 低～中 | 地区全域分類等、誤分類に強い広帯域に限定 |
| 正確な物件位置取得後の主・補完分析 | 中～高 | 件数・平行トレンド・震災交絡を通過すれば有力 |
| 地価公示・地価調査での距離形状確認 | 中 | 位置は正確だが処置地点数が少ない |

現状では、候補5は**メカニズム・空間範囲を調べる将来拡張または探索分析**であり、公開不動産取引価格情報を使う主分析ではない。まず候補4のfeasibility auditを行い、正確な位置情報の取得可能性を別途調べるべきである。

## 10. 具体的な実装手順

1. **estimandを事前固定**: 土地取引の円/m²、2013Q1移行期、2013Q2以後post、2017Q4で主窓終了とする。
2. **API/CSVを取得**: 日立市と候補対照市町村について、2007--2017年、価格情報区分01を取得し、取得日・query・原ファイルhashを保存する。
3. **物件種別を分離**: 宅地（土地）を主標本、土地建物・中古マンションを独立補助標本にする。
4. **地区crosswalkを作る**: `DistrictName`・`DistrictCode`の年次出現、表記揺れ、合併・境界を監査する。機械的にコードを恒久IDとみなさない。
5. **公式地区ポリゴンへ対応付け**: 対応不能・複数候補をフラグ化し、人手確認ログを残す。
6. **位置不確実性表を作る**: 各地区の停留所への`d_min/d_max`、専用路への`d_min/d_max`、面積、形状を計算する。
7. **feasibility gateを通す**: 確実処置・確実遠方の年別取引数、イベントbin別セル数、属性欠損を出す。閾値未満なら候補5を中止する。
8. **記述統計を先に作る**: 取引件数、価格分布、属性分布、地区地図、震災浸水、競合事業を表示する。
9. **候補4を基準推定**: 粗い地区曝露×post/event-timeのヘドニックDIDを推定する。
10. **候補5の縮退版**: 地区全域が入る広い距離帯だけでringを推定し、曖昧地区を除外する。結果を「物件距離効果」と呼ばない。
11. **位置誤差感度を実行**: 重心、全域確実分類、境界除外、複数位置分布の全結果を並べる。
12. **震災・spillover・構成診断**: 浸水域、donut、対照外径、物件属性DID、取引件数を確認する。
13. **正確な位置を得られた場合だけ本来の候補5へ進む**: 停留所・専用路への距離を作り、事前固定ringイベントスタディ、Conley推論、距離曲線・一様帯を実行する。
14. **報告を格付け**: `exact parcel / certain district / centroid proxy`を結果表の各列に明記し、位置品質が異なる推定を同列に扱わない。

## 主要一次資料・原論文

- 国土交通省「[不動産取引価格情報提供制度](https://www.mlit.go.jp/totikensangyo/totikensangyo_tk5_000069.html)」
- 不動産情報ライブラリ「[不動産価格情報取得API XIT001](https://www.reinfolib.mlit.go.jp/help/apiManual/xit001/)」
- 不動産情報ライブラリ「[不動産価格情報のポイントAPI XPT001](https://www.reinfolib.mlit.go.jp/help/apiManual/xpt001/)」
- 不動産情報ライブラリ「[制度と用語](https://www.reinfolib.mlit.go.jp/realEstatePrices/about/)」
- 日立市「[新交通導入計画を策定しました](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html)」
- Butts, K. (2023), “[JUE Insight: Difference-in-differences with geocoded microdata](https://doi.org/10.1016/j.jue.2022.103493).”
- Butts, K., “[Difference-in-Differences Estimation with Spatial Spillovers](https://www.kylebutts.com/files/Spillover.pdf).”
- Diao, M., Leonard, D. and Sing, T. F. (2017), “[Spatial-difference-in-differences models for impact of new mass rapid transit line on private housing values](https://doi.org/10.1016/j.regsciurbeco.2017.08.006).”
- Gibbons, S. and Machin, S. (2005), “[Valuing Rail Access Using Transport Innovations](https://eprints.lse.ac.uk/19989/1/Valuing_Rail_Access_Using_Transport_Innovations.pdf).”
- Chen, H., Rufolo, A. and Dueker, K. (1998), “[Measuring the Impact of Light Rail Systems on Single-Family Home Values](https://doi.org/10.3141/1617-05).”
- Ahlfeldt, G., Nitsch, V. and Wendland, N. (2016), “[Ease vs. Noise](https://www.ifo.de/DocDL/cesifo1_wp6058.pdf).”
- Arbia, G. et al. (2015), “[Measurement Errors Arising When Using Distances in Microeconometric Modelling](https://doi.org/10.3390/econometrics3040709).”
- `fixest`「[Conley VCOV](https://lrberge.github.io/fixest/reference/vcov_conley.html)」
- `binsreg`「[Data-Driven Binscatter Least Squares Regression](https://search.r-project.org/CRAN/refmans/binsreg/html/binsreg.html)」
- `sf`「[Compute geometric measurements](https://r-spatial.github.io/sf/reference/geos_measures.html)」
