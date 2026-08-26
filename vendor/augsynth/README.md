# Patched `augsynth` source package

`augsynth_0.2.0.9000.tar.gz` は、公式リポジトリのコミット
`7a90ea48877fae7925a72cb50bc03a315bc7c042` に
`augsynth-dplyr-1.2.patch` を適用して作成したソースパッケージである。

`augsynth 0.2.0` の `single_augsynth()` は、処置単位を記録するときに
`pull(quo_name(unit))` を使用する。この式は `dplyr 1.2.x` では列名を
正しく選択できないため、すでに同じ関数内で使われている tidy evaluation
形式の `pull(!!unit)` へ置き換えた。解析ロジックや推定処理は変更していない。

- upstream: <https://github.com/ebenmichael/augsynth>
- upstream commit: `7a90ea48877fae7925a72cb50bc03a315bc7c042`
- SHA-256: `C9A68628AB7C5A9A2056097065C22F9EC2BC8A2DA2E5249961EC0B46F175A8D5`

再ビルドする場合は upstream commit を checkout し、パッチを適用してから
次を実行する。

```powershell
R CMD build --no-build-vignettes --no-manual augsynth
```
