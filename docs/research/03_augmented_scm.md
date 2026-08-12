# 候補3：Augmented Synthetic Control Method（ASCM）

> **位置づけ：参考資料・適用可能性未検証**
> この文書は分析手法の参考調査である。ひたちBRTの実データについて、年度別標本数、継続地点、対照候補、空間配置などを十分に確認する前に作成された。本文中の「推奨」「主分析」「適性」などの評価は現在の研究方針では確定事項ではなく、手法候補の採否は未評価である。現在の位置づけは [`docs/method_candidates.md`](../method_candidates.md) と有効な[意思決定ログ](../decision_logs/README.md)を正本とする。

調査日: 2026-08-12
対象: ひたちBRT第I期が沿線地価に及ぼした影響
位置づけの暫定結論: **主分析ではなく、地域集計レベルの補完分析・頑健性確認として条件付きで採用**

## 要約

Augmented Synthetic Control Method（ASCM）は、通常のSynthetic Control Method（SCM）が作る合成対照に、アウトカム回帰による「不完全な事前適合のバイアス補正」を加える方法である。原論文の主提案であるRidge ASCMは、通常のSCMより事前適合を改善する代わりに負のドナー重みを許すが、リッジ正則化によってSCM重みからの乖離、すなわち外挿を抑える。[Ben-Michael, Feller, and Rothstein (2021), JASA](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

ひたちBRTでは、沿線の地価公示地点が少ないため、個々の地点をそのまま「一つの処置単位」とするより、**第I期沿線の固定地点から価格指数を作って一つの処置地域とし、同じルールで作った複数の非沿線地域をドナーとする**のがASCMの自然な適用である。ただし、少数地点を集計しても元の情報量は増えない。処置地域の境界、固定地点の残存数、ドナー地域の作り方に結果が強く依存する。

さらに、日立市は2009年の跡地活用基本構想を受けて2010年度に検討委員会を置き、新交通導入計画を公表しているため、2013年3月の運行開始より前に期待効果が生じた可能性がある。[日立市「新交通導入計画を策定しました」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html) また、第I期沿線を含む久慈地区では東日本大震災後の復興交付金事業が行われており、2011年以後の地価変化をBRTだけに帰属させにくい。[日立市「東日本大震災復興交付金事業計画」](https://www.city.hitachi.lg.jp/kurashi_tetsuzuki/anzen_anshin/1004772/1000011/1004947/1004963.html)

したがってASCMは、良いドナーと安定した価格指数を構築できた場合に、固定地点DIDとは異なる集計レベルの反実仮想を示す**補完分析**として価値がある。一方、現段階で主分析に据えるのは推奨しない。

## 1. 何を推定する方法か

### 1.1 基本的なestimand

標準的な単一処置単位の設定では、単位 \(i=1\) が処置され、他の単位は処置されない。時点 \(t\) の処置効果は、処置単位について

\[
\tau_{1t}=Y_{1t}(1)-Y_{1t}(0)
\]

である。観測できない \(Y_{1t}(0)\) を、ドナー地域のアウトカムの重み付き和で予測する。ASCM原論文は、一つの処置単位、固定された単位・時点数、処置単位間の干渉がないSUTVAを基本設定としている。[Ben-Michael, Feller, and Rothstein (2021), Sections 2.1–2.2](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

本研究で推定したい量は、例えば次のように具体化できる。

> 第I期沿線として事前に定義した地域内の固定された地価公示地点の幾何平均価格が、ひたちBRT第I期がなかった場合に比べ、各年に何%変化したか。

アウトカムを地域 \(z\)、年 \(t\) の平均対数地価

\[
Y_{zt}=\frac{1}{n_z}\sum_{p\in z}\log(Price_{pt})
\]

とすれば、ASCMのギャップ \(\hat\tau_t\) は平均対数地価への効果である。百分率換算は \(100\{\exp(\hat\tau_t)-1\}\) とする。

このestimandは「第I期沿線にある全不動産の平均効果」ではなく、**採用した固定標準地バスケットの価格指数への地域集計効果**である。国土交通省も、地価公示は毎年1月1日時点における特定の標準地の単位面積当たり正常価格であり、近隣のすべての土地の価格を一律に示すものではないとしている。[国土交通省「地価公示制度の概要」](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000132.html) [不動産情報ライブラリ「地価公示・都道府県地価調査」](https://www.reinfolib.mlit.go.jp/landPrices/about/)

### 1.2 識別の考え方と前提

通常のSCMは、処置単位の事前アウトカムと共変量に近くなるよう、非負で合計1のドナー重みを選ぶ。処置単位がドナーの凸包内にあり、事前適合が良い場合には透明で外挿の少ない反実仮想になる。[Abadie (2021), Sections 3 and 6](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)

ASCMは、通常のSCMによる予測に、処置単位と合成対照の事前アウトカム差からアウトカム回帰で推定した補正を加える。Ridge ASCMは負の重みを許して事前適合を改善するが、リッジのハイパーパラメータ \(\lambda\) がSCM重みからの乖離を罰し、適合改善と外挿の間を調整する。[Ben-Michael, Feller, and Rothstein (2021), Sections 3–5](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

原論文は主に、(a) 処置後アウトカムが事前アウトカムの線形結合で表される過程、または (b) 線形潜在因子モデルの下で誤差を評価する。潜在因子モデルは観測されない交絡を因子負荷として許す一方、処置選択が実現した一時的ショックに依存しないこと、誤差が平均ゼロであることなどを要する。[Ben-Michael, Feller, and Rothstein (2021), Assumption 1 and Section 7.2](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

ひたちBRTへの翻訳は次のとおりである。

- BRTがなかった場合の第I期沿線の地価動向を、ドナー地域の加重平均と安定したアウトカム関係で予測できる。
- ドナー地域はBRTや同種の交通介入を受けず、第I期からの地価格 spillover も受けない。
- 震災復興、工場再編、港湾投資、道路整備など、処置後に第I期沿線だけを動かすショックが、事前価格経路や共変量で予測できない形で残らない。
- 正式開業より前に土地市場が計画を織り込まない、または処置時点を期待形成開始まで遡らせる。

ASCMは通常のDIDの平行トレンド仮定と同じものを直接置く方法ではないが、**事前適合が良ければ自動的に因果効果が識別されるわけではない**。適切なドナー、処置前だけを用いた設計、干渉なし、処置後の固有ショックがないという研究設計上の議論が必要である。[Abadie (2021), Sections 6–7](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)

## 2. 処置単位とアウトカム集計

### 2.1 推奨する処置単位

基準案は、**2013年3月25日にBRT取扱いを開始した当初11停留所のバッファを結合した地域**である。第I期が2005年に廃止された日立電鉄線跡を利用し、2013年3月から運行を開始したことは茨城県議会資料にも明記されている。[茨城県議会「交通政策・物流問題調査特別委員会資料」](https://www.pref.ibaraki.jp/gikai/report/koutsu_butsuryu/02/setsumeichoshu.pdf)

処置境界は結果を見て選ばず、次の順で事前指定する。

1. 基準: 当初11停留所から1.5 km以内かつ第I期ルートの対象範囲にある地点。
2. 狭い範囲の感度分析: 800 m以内。
3. 連続した回廊の感度分析: 第I期ルート中心線から一定距離のバッファ。

リポジトリ内の既確認値では、2013年の地価公示地点は800 m以内4地点、1.5 km以内7地点にすぎない。この少なさはASCMを使っても消えず、地域価格指数の測定誤差と地点選択への感度として残る。

### 2.2 アウトカム候補の優先順位

| 優先 | アウトカム | 長所 | 問題 |
|---|---|---|---|
| 1 | 全期間で同じ地点から作る平均対数地価（固定バスケット） | 構成変化を最も抑えられる | 継続地点を求めると沿線地点がさらに減る |
| 2 | 前年と共通する地点で作る連鎖指数 | 各年の利用地点を増やせる | 連鎖ドリフト、年ごとの構成変化 |
| 3 | 地点属性を調整した地域年価格指数 | 用途・道路・面積の変化を調整できる | 地価公示地点数が少なく、指数作成モデル自体への依存が増す |

地価公示データは位置、公示価格、利用現況、用途地域、地積等を持つGISデータとして公開されている。[国土数値情報「地価公示」](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L01-2026.html) 一方、標準地は毎年点検され、不適格なら選定替えされるため、地点番号が同じに見えることだけで固定地点とみなさず、座標、所在地、地積、利用区分を使った履歴クロスウォークと目視確認が必要である。[国土交通省「地価公示制度の概要」](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000132.html)

住宅地、商業地、工業地の価格水準と市場は異なるので、基準結果は用途を一つに限定するか、少なくとも用途別指数を作る。用途を混ぜる場合は、各地域で固定した用途構成の重みを使い、年々の構成変化を許さない。

### 2.3 推奨しない集計

- 第I期沿線の複数地点を平均した系列に対し、ドナーを「個別の地価地点」とする。集計地域と単一点で測定誤差・用途構成が非対称になる。
- 日立市全体を処置単位とする。第I期は市の一部だけなので処置が希釈され、市内の別ショックを多く含む。
- 2013年以後に観測された人口・土地利用を予測因子にする。BRTの影響を受ける媒介変数を事後調整するおそれがある。

## 3. ドナープール設計

### 3.1 第一候補：同一ルールの疑似回廊地域

第I期処置地域と同じ面積、同程度の都市化度、同程度の地価公示地点数になるよう、茨城県内の非BRT地域に非重複の「疑似回廊」を作る。各ドナーも、固定された複数地点の平均対数地価をアウトカムとする。

ドナー候補の生成ルールは、処置後の地価を見ずに固定し、次を満たすようにする。

- 最低限必要な継続地価地点数を満たす。
- 人口密度、2000–2010年人口変化、土地利用構成、JR駅距離、海岸距離、道路アクセスが処置地域と極端に異ならない。
- 2013年以後にBRT、鉄道開廃、駅新設、大型再開発など明確な同種介入を受けた地域を除く。
- 第I期および第II期回廊から十分離し、直接の地価spilloverを受けそうな地域を除く。

Abadieは、ドナーには同種介入を受けた単位を含めず、大きな固有ショックを受けた単位を除き、処置単位と似た特性の単位に制限することを推奨している。[Abadie (2021), “Availability of a Comparison Group” and “No Interference”](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)

### 3.2 二つのドナープールを事前指定する

一つのプールに都合よく依存しないため、次の二つを別々に推定する。

**A. 日立市内・近隣プール**

- 長所: 日立製作所、地域景気、自治体政策など共通ショックを受けやすい。
- 短所: BRTのネットワーク効果や期待、道路交通の付け替えが波及する可能性が高い。

**B. 茨城県内類似都市プール**

- 長所: 第I期からの直接spilloverを避けやすい。
- 短所: 日立市固有の産業・復興・人口動態を再現しにくい。

地理的に近い単位は共通地域ショックを共有しやすい一方、近すぎるとspilloverを受けるという緊張関係があるため、両プールの一致・不一致自体を結果として報告する。[Abadie (2021), “No Interference”](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)

### 3.3 震災復興への対応

日立市は東日本大震災後、久慈地区を含む復興交付金事業を実施している。[日立市「東日本大震災復興交付金事業計画」](https://www.city.hitachi.lg.jp/kurashi_tetsuzuki/anzen_anshin/1004772/1000011/1004947/1004963.html) したがって、単純に内陸地域だけをドナーにすると、沿岸復興との違いがBRT効果に混ざり得る。

対応は一つに決め打ちせず、次を行う。

1. 海岸距離、津波浸水・復興事業地域、2010–2012年価格変化を予測因子に含める。
2. 沿岸類似地域だけのドナープールと、広い茨城県プールを別推定する。
3. 2011年前後のgap plotを特に点検する。
4. 復興事業を受けた高重みドナーがあれば、その事業内容を調べ、leave-one-donor-outを行う。

これは完全な解決ではない。第I期沿線だけの復興投資がBRTと同時に進み、事前系列から予測不能なら、ASCMでも分離できない。

## 4. 予測因子

予測因子は、処置後の値を使わず、2013年より前に確定しているものに限定する。

### 4.1 最小構成

1. **事前の平均対数地価系列**: 可能なら2000–2013年の各年。
2. **価格トレンド**: 2000–2005、2005–2010、2010–2013の変化率。ただし全事前年を直接使う場合は重複が大きいので、感度分析用とする。
3. **2010年人口密度と2000–2010年人口変化**。
4. **2010年以前の年齢構成・世帯構成**: 入手可能な範囲。
5. **処置前土地利用比率**: 建物用地、工業用地、農地、水面等。
6. **交通・立地**: JR駅距離、主要道路距離、海岸距離、旧鉄道・バス路線への近接。
7. **地価地点の構成**: 住宅・商業・工業の比率、地点数、前面道路・用途地域等の事前平均。
8. **震災関連**: 津波浸水実績、沿岸ダミー、2011年前後の価格下落。

リポジトリにある国勢調査4次メッシュは約500 mの地域区画に対応する。総務省統計局は標準地域メッシュとして、第3次区画を約1 km、その分割区画をさらに細分する体系を定めている。[総務省統計局「地域メッシュ統計について」](https://www.stat.go.jp/data/mesh/m_tuite.htm) 土地利用細分メッシュは100 mメッシュで土地利用を分類した政府データである。[国土数値情報「土地利用細分メッシュ」](https://nlftp.mlit.go.jp/ksj/jpgis/datalist/KsjTmplt-L03-b-v1_1.html)

人口メッシュと土地利用メッシュは、処置・ドナー地域ポリゴンとの面積按分または重心包含で集計できる。ただし2015年・2020年国勢調査は処置後なので、地価の予測因子には使わない。将来、人口を別のアウトカムとして分析する場合にのみ使う。

### 4.2 共変量を増やしすぎない

原論文は、補助共変量が中程度なら事前アウトカムと標準化した共変量を並行して入れ、共変量数がドナー数に比べ少ない場合は、共変量でアウトカムを残差化してからRidge ASCMを適用する二段階法も示している。[Ben-Michael, Feller, and Rothstein (2021), Section 6](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

本研究ではドナー地域数が多くない可能性が高いため、共変量は理論上重要な少数に絞る。結果を見て共変量を追加・削除せず、候補集合を事前に記録する。

## 5. 処置時点と事前期間

### 5.1 開業時点を使う仕様

地価公示は毎年1月1日時点の価格である。[国土交通省「地価公示」](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000043.html) 第I期の運行開始は2013年3月なので、年次パネルでは次のように符号化する。

- 2013年地価公示: 開業前。
- 最初の処置後観測: 2014年地価公示。
- `treated = 1` は処置地域かつ `year >= 2014`。
- `t_int = 2014`。

手元の2000–2025年地価公示を使えるなら、開業仕様の事前期間は2000–2013年の14時点になる。原論文のハイパーパラメータ選択は、事前年を一つずつ外す時点方向の交差検証を提案している。[Ben-Michael, Feller, and Rothstein (2021), Section 5.3](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

### 5.2 期待形成を含める仕様

正式開業より前に計画が公表されている。日立市資料によれば、2009年3月の跡地活用基本構想を受け、2010年度に新交通導入計画をまとめている。[日立市「新交通導入計画を策定しました」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html) 土地市場が将来のアクセシビリティを予想するなら、2013年開業仕様の「期待効果なし」は弱い。

Abadieは期待効果が疑われる場合、介入時点を期待が始まり得る時点まで遡らせることを提案している。[Abadie (2021), “No Anticipation”](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf) そこで感度分析として、2009年構想または2010年計画を介入時点にする。ただし、2009年に遡ると2000–2008年の9事前時点しかなくなり、適合・交差検証・推論が弱くなる。また効果は「運行開始効果」ではなく、計画公表、期待、工事、運行開始を合わせた**プロジェクト総効果**になる。

### 5.3 分析期間の切り分け

第I期だけの効果を明確にするため、次の窓を分ける。

- **主たる第I期窓**: 2014–2017年。2018年3月の第II期先行運行より前。
- **拡張窓**: 2014–2025年。2016年の停留所追加、第II期、2019年の運行再編を含む「進化したBRTネットワーク」の効果としてのみ解釈。
- **初期固定サービス窓**: 2014–2015年。2016年の「日立商業高校」追加前だが、処置後が2時点しかないため記述的確認に限る。

開業・停留所変更の詳細は、リポジトリ内の [`docs/hitachi_brt_stop_openings_research.md`](../hitachi_brt_stop_openings_research.md) に整理されている。

## 6. 小標本、外挿、適合、spillover、推論

### 6.1 小標本

ASCMにおける名目上の処置単位数は一つなので、沿線地点4–7という少なさは通常の回帰の「処置群クラスタ数」ではなく、**処置地域価格指数の精度と代表性**の問題になる。しかし、集計は新しい情報を作らない。1地点の選定替えや用途の違いが指数を大きく動かす可能性がある。

事前時点も、開業仕様で14年、期待形成仕様で9年に限られる。Abadieは事前期間が短いと一時的ショックに過剰適合しやすく、事前期間を長くすることには構造変化とのトレードオフがあると説明している。[Abadie (2021), “Predictive Power and Over-Fitting”](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)

### 6.2 必須の適合・外挿診断

ASCMを採用する最低条件として、次をすべて報告する。

1. 処置地域と合成対照の事前・事後系列。
2. 年別gap plot。
3. 通常SCMとRidge ASCMの事前RMSPE、L2 imbalance、均等重みからの改善率。
4. 共変量バランス。
5. ドナー重み一覧。
6. 負の重みの総絶対値、最小重み、最大絶対重み。
7. SCM重みとASCM重みの距離。
8. 高重みドナーを一つずつ外すleave-one-donor-out。
9. 事前期間の後半を疑似処置後にしたin-time placebo。

Ridge ASCMは通常のSCM以上の事前適合を達成するが、それは負の重みによる外挿を許すためでもある。原論文は、SCM適合が良いときに小さすぎる \(\lambda\) で過度に補正するとRMSEが悪化し得るため、外挿量を直接診断することを重視している。[Ben-Michael, Feller, and Rothstein (2021), Sections 4–5 and 7.1](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

「ASCMなら悪いSCM fitを必ず救える」とは解釈しない。大きな負の重みが必要、処置地域がドナーの範囲から極端に外れる、またはholdout事前期間を予測できない場合は、ドナープール不適格として結果を主張しない。

### 6.3 spillover

SCMの基本設定は単位間干渉なしを要する。BRTが市内の人口・商業・不動産需要を沿線へ移し、非沿線地価を下げるなら、市内ドナーは「未処置」ではない。逆に、市全体のアクセシビリティ改善が非沿線にも便益を与える可能性もある。

対策は次のとおりである。

- 第I期から0–3 km、3–5 kmなどの除外帯を変える感度分析。
- 市内ドナーと市外ドナーを分ける。
- 第II期・第III期予定地を全期間のドナーから除く。
- 市内プールの推定量は「直接効果」ではなく、市内非沿線に対する相対効果と明記する。

干渉のおそれがある単位をドナーから除くことはSCM設計の基本的対応である。[Abadie (2021), “No Interference”](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)

### 6.4 推論とplacebo

`augsynth` の `summary()` は、conformal、jackknife+、unit jackknife、raw permutation、RMSPE調整permutationを選択でき、既定はconformal inferenceである。[公式 `summary.augsynth` ドキュメント](https://github.com/ebenmichael/augsynth/blob/master/man/summary.augsynth.Rd)

原論文のconformal inferenceは、鋭い帰無仮説の下で処置後アウトカムを調整し、その残差が事前残差と比べて極端かを評価する。時点間の残差が交換可能なら有限標本で正確だが、交換可能でない場合の妥当性は事前期間が増える漸近論などに依存する。[Ben-Michael, Feller, and Rothstein (2021), Section 5.4](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)

年次地価はトレンドと系列相関が想定され、事前14時点も長くないため、conformal区間を機械的に「正確な95%信頼区間」と呼ばない。次を並記する。

- pointwise conformal interval/p-value。
- 各ドナーを仮処置したin-space placeboのgapとpost/pre RMSPE比。
- `permutation_rstat` のRMSPE調整結果。
- in-time placebo。
- leave-one-donor-out。

通常のin-space placeboでは、事前適合が処置単位より大幅に悪いプラセボを同列に扱わず、post/pre RMSPE比や適合フィルタを用いることが提案されている。[Abadie (2021), Section 3.5](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf) `augsynth` はドナーごとのplacebo分布とRMSPEを取得する関数も提供する。[公式 `placebo_distribution` ドキュメント](https://github.com/ebenmichael/augsynth/blob/master/man/placebo_distribution.Rd) [公式 `donor_table` ドキュメント](https://github.com/ebenmichael/augsynth/blob/master/man/donor_table.Rd)

ドナーが \(J\) 個なら、単純な順位型placebo p値の最小刻みは \(1/(J+1)\) である。このためドナー数が少ない場合、統計的有意性より、効果の大きさ、事前適合、placebo中での順位、感度を中心に報告する。

## 7. R実装

### 7.1 パッケージ

著者の公式Rパッケージは [`ebenmichael/augsynth`](https://github.com/ebenmichael/augsynth) である。公式READMEはGitHubからのインストールを案内し、単一処置単位は `single_augsynth`、複数の処置時点は `multisynth`、単一処置単位・複数アウトカムは `augsynth_multiout` として実装している。[公式README](https://github.com/ebenmichael/augsynth)

再現性のため、導入時にはGitHubのコミットSHAを固定して `renv.lock` に記録する。例:

```r
remotes::install_github("ebenmichael/augsynth@<commit-sha>")
renv::snapshot()
```

### 7.2 入力パネル

`augsynth()` は、アウトカム、処置指標、単位、時点、データ、介入時点を受け取る。[公式 `augsynth` ドキュメント](https://github.com/ebenmichael/augsynth/blob/master/man/augsynth.Rd) 入力は次のlong形式にする。

| zone_id | year | log_price_index | treated | pop_density_2010 | pop_growth_00_10 | built_share_pre | coast_dist_km |
|---|---:|---:|---:|---:|---:|---:|---:|
| hitachi_phase1 | 2000 | … | 0 | … | … | … | … |
| hitachi_phase1 | 2014 | … | 1 | … | … | … | … |
| donor_001 | 2000 | … | 0 | … | … | … | … |

全地域・全年についてアウトカムがそろうbalanced panelを基準とする。欠測を補間して見かけ上そろえるのではなく、固定地点バスケットとドナー地域の構築段階で整合させる。

### 7.3 基本コード案

```r
library(augsynth)

fit_ridge <- augsynth(
  log_price_index ~ treated |
    pop_density_2010 +
    pop_growth_00_10 +
    built_share_pre +
    industrial_share_pre +
    jr_station_dist_km +
    coast_dist_km +
    tsunami_exposure,
  unit = zone_id,
  time = year,
  data = zone_panel,
  t_int = 2014,
  progfunc = "ridge",
  scm = TRUE,
  fixedeff = TRUE
)

fit_scm <- augsynth(
  log_price_index ~ treated |
    pop_density_2010 + pop_growth_00_10 + built_share_pre,
  unit = zone_id,
  time = year,
  data = zone_panel,
  t_int = 2014,
  progfunc = "none",
  scm = TRUE,
  fixedeff = TRUE
)

sum_conf <- summary(fit_ridge, inf_type = "conformal")
sum_perm <- summary(fit_ridge, inf_type = "permutation_rstat")

donor_table(fit_ridge)
covariate_balance_table(fit_ridge)
placebo_distribution(sum_perm)

plot(sum_conf)
```

`single_augsynth()` の既定アウトカムモデルはridge、`scm = TRUE`なら事前共変量に合わせたドナー重みを計算し、戻り値にはASCM重み、L2 imbalance、均等重みで標準化したL2 imbalance、アウトカムモデル等が含まれる。[公式 `single_augsynth` ドキュメント](https://github.com/ebenmichael/augsynth/blob/master/man/single_augsynth.Rd)

`fixedeff = TRUE` は地域固有の価格水準差を許し、価格変化を合わせやすくする候補である。代替として、各地域の平均対数地価から事前平均を引いた指数を作り `fixedeff = FALSE` で推定し、両者を感度分析にする。通常SCM、Ridge ASCM、均等重み、単純DID型の地域平均を同じ図で比較する。

## 8. ひたちBRTでの実現可能性と主分析適性

### 8.1 実現可能性

| 要素 | 評価 | 理由 |
|---|---|---|
| 年次アウトカム | 中 | 2000年以降の地価公示があるが、固定地点クロスウォークが必要 |
| 処置地域 | 中 | 停留所履歴は整備済みだが、800 mか1.5 kmかで対象地点が大きく変わる |
| ドナー数 | 未確認 | 同じ地点数・用途構成を持つ疑似回廊を何個作れるか実査が必要 |
| 事前期間 | 中～低 | 開業仕様14年、期待形成仕様9年。2011年の大きな構造変化を含む |
| 予測因子 | 中～高 | 人口メッシュ、土地利用、行政区域、鉄道時系列が手元にある |
| spillover回避 | 中～低 | 市内ドナーは共通ショックに強いがBRT波及を受け得る |
| 因果解釈 | 低～中 | 震災復興、事前期待、2016年追加、2018年以後の第II期が重なる |

### 8.2 主分析にしない理由

1. **処置単位が自然な行政単位ではない。** 第I期沿線バッファという研究者作成の地域であり、境界変更で結果が変わり得る。
2. **処置地域指数が少数地点から成る。** ASCMは処置地点数不足を統計的に解消しない。
3. **ドナー地域も研究者が作る。** 同一ルールで透明に作れるかが成否を決める。
4. **期待効果が疑われる。** 2009–2010年に計画が公表され、2013年を純粋な開始点としにくい。[日立市「新交通導入計画を策定しました」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html)
5. **2011年震災復興との分離が難しい。** 久慈地区で復興事業が実施された。[日立市「東日本大震災復興交付金事業計画」](https://www.city.hitachi.lg.jp/kurashi_tetsuzuki/anzen_anshin/1004772/1000011/1004947/1004963.html)
6. **第I期だけの安定した処置期間が短い。** 2016年に停留所追加、2018年から第II期先行運行がある。

### 8.3 適切な位置づけ

**推奨: 補完分析／地域集計レベルの頑健性確認。**

- 固定地点イベントスタディDIDが地点レベルの効果を示すのに対し、ASCMは「第I期沿線全体の価格指数」に対する別の反実仮想を示す。
- DIDで平行トレンドが弱い場合、事前経路を加重して近づけるASCMがどこまで改善するかを診断できる。
- 結果がDIDと同方向で、事前fitが良く、外挿が小さく、ドナープール感度にも耐える場合に限り、結論を補強する。
- 結果が不一致なら、効果の有無を多数決で決めず、処置境界、集計、spillover、期待・復興ショックのどれが違いを生むかを検討する。

**主分析へ昇格できる最低条件**は、(a) 1.5 km以内で少なくとも複数の全期間継続地点が残る、(b) 同一生成ルールで十分な数の比較可能なドナー地域を作れる、(c) 通常SCMまたは軽いaugmentationで良いholdout事前予測が得られる、(d) 負の重みが極端でない、(e) 市内・市外ドナーで結論が大きく変わらない、のすべてを満たすことである。

## 9. 具体的な実装手順

### Phase A: 実行可能性監査

1. 2000–2025年の地価公示を統一スキーマにする。
2. 座標、所在地、標準地番号、地積、用途を使って地点履歴をクロスウォークする。
3. 2000–2017、2000–2025の二つのbalanced fixed-site panelで、第I期800 m・1.5 km内に何地点残るか数える。
4. 住宅地のみ、全用途固定構成の両方を数える。
5. ここで処置地点が1–2しか残らなければ、地価公示ASCMは中間発表の推定候補から外し、設計案のみ示す。

### Phase B: 空間単位の固定

6. 当初11停留所と2013年ルートから、800 m、1.5 km、ルートバッファの3処置ポリゴンを作る。
7. 同面積・同程度の地点数を持つ疑似回廊の自動生成ルールをコード化する。
8. Phase II/III、他の大規模交通介入、処置周辺除外帯を適用する。
9. 処置後価格を見ず、2010年人口、事前土地利用、交通・沿岸条件で候補をトリミングする。
10. 採用・除外した全ドナーと理由をCSVに残す。

### Phase C: 地域価格指数と共変量

11. 地域ごとに固定バスケット平均対数地価を作る。
12. 国勢調査メッシュから2010年人口密度、2000–2010年人口変化、事前年齢・世帯構成を集計する。
13. 2009年以前の土地利用から建物、工業、農地等の比率を集計する。
14. JR駅、主要道路、海岸、旧鉄道からの距離を計算する。
15. 津波・復興曝露の指標を追加し、すべて処置前情報であることをデータ辞書に記録する。

### Phase D: 推定

16. 通常SCMを先に推定する。
17. Ridge ASCMを推定し、交差検証で \(\lambda\) を選ぶ。
18. 共変量なし、少数共変量、残差化仕様を比較する。
19. 開業仕様（最初の処置後地価=2014）と期待形成仕様（2009または2010）を分ける。
20. 第I期窓2014–2017を主に報告し、2018年以後はネットワーク拡張を含む別結果とする。

### Phase E: 診断・推論

21. actual vs synthetic、gap、pre-RMSPE、L2 imbalance、共変量バランス、重みを出す。
22. 負の重みとSCM重みからの距離を出す。
23. in-time placebo、in-space placebo、RMSPE比を出す。
24. leave-one-donor-outを行う。
25. 800 m、1.5 km、ルートバッファ、市内・市外ドナープールで結果表を作る。

### Phase F: 判断基準

26. holdout事前予測が悪い、極端な負重みが必要、特定ドナー除外で符号が変わる場合は「ASCMは実行したが信頼できる反実仮想を構築できなかった」と報告する。
27. fitと感度が良い場合でも、震災復興と期待効果を完全に除いたとは主張せず、「地域集計レベルの補完的証拠」とする。

## 10. 中間発表で示すべき最小成果物

1. 処置地域・ドナー地域の地図。
2. 各地域の固定地価地点数と用途構成。
3. 処置地域と通常平均対照の事前推移。
4. 処置地域とSCM/ASCMの系列図、gap plot。
5. donor weightsと負の重み。
6. pre-RMSPE・holdout RMSPE。
7. placebo分布。
8. 800 m/1.5 km、市内/市外ドナー、開業/期待形成時点の感度表。
9. 「この推定量が表す対象」と「表さない対象」の明記。

## 主要一次資料

- Eli Ben-Michael, Avi Feller, and Jesse Rothstein, [“The Augmented Synthetic Control Method,” JASA 116(536), 2021](https://jesse-rothstein.com/wp-content/uploads/2021/07/Ben-Michael_Feller_Rothstein_Augsynth_JASA_2021.pdf)
- 著者公式R実装, [`ebenmichael/augsynth`](https://github.com/ebenmichael/augsynth)
- Alberto Abadie, [“Using Synthetic Controls: Feasibility, Data Requirements, and Methodological Aspects,” JEL 59(2), 2021](https://conference.nber.org/confer/2021/SI2021/Abadie_2021.pdf)
- 国土交通省, [「地価公示制度の概要」](https://www.mlit.go.jp/totikensangyo/totikensangyo_fr4_000132.html)
- 国土数値情報, [「地価公示」](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L01-2026.html)
- 総務省統計局, [「地域メッシュ統計について」](https://www.stat.go.jp/data/mesh/m_tuite.htm)
- 国土数値情報, [「土地利用細分メッシュ」](https://nlftp.mlit.go.jp/ksj/jpgis/datalist/KsjTmplt-L03-b-v1_1.html)
- 日立市, [「新交通導入計画を策定しました」](https://www.city.hitachi.lg.jp/machizukuri_kankyo/shigaichiseibi/1002785/1002795.html)
- 日立市, [「東日本大震災復興交付金事業計画」](https://www.city.hitachi.lg.jp/kurashi_tetsuzuki/anzen_anshin/1004772/1000011/1004947/1004963.html)
