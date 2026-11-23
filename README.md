# NEON GEOMETRY ― 幾何学サバイバー

Godot 4.7 で作っている、ヴァンパイアサバイバー系の個人学習用ゲームです。
迫ってくる図形の敵を、自動で攻撃する武器で倒しながら 3 分間生き残り、スコアを競います。

画像・音声などの外部素材は一切使わず、見た目はすべてコードで描いた図形と HDR グローで表現しています。

**ライセンス:** 作者オリジナルのソースコードは [MIT License](LICENSE) です。
同梱フォント（M PLUS 1 / Noto Sans Symbols 2）は SIL Open Font License 1.1、Godot およびその他の第三者部品は [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt) に従います。

## リリース（GitHub Releases）

`v1.0.0` のような SemVer タグを `main` に付けると、Windows 向けの zip と案内 PDF が GitHub Releases に公開されます（`.github/workflows/release.yml`）。
Release 上の案内 PDF は `NEON_GEOMETRY-guide.pdf`（GitHub が日本語ファイル名を扱えないため）。zip の中には従来どおり `幾何学サバイバー（NEON GEOMETRY）のご紹介.pdf` が入っています。

```powershell
# 例（バージョンとタグはユーザーが明示したときだけ）
# project.godot の config/version を揃えたうえで:
git tag v1.0.0
git push origin v1.0.0
```

手元だけで作る場合は、従来どおり `tools\export\export_windows.ps1` を実行し、`build\` の zip と案内 PDF を使います。

## 遊び方

| 操作 | キー |
|---|---|
| 移動 | WASD / 方向キー |
| ポーズ | Esc / P |
| タイトルで開始 | Enter / Space |
| リザルトからリトライ | Enter / Space / R |

- 攻撃は自動です。移動に専念して敵をかわし、経験値を集めます。
- レベルアップごとに 3 つの候補から 1 つを選び、武器やパッシブを強化します（武器・パッシブは各 4 枠）。
- 3 分間生き残るとクリアです。撃破スコアにクリアボーナスと残り HP ボーナスが加わります。
- タイトル画面から、日時付きのハイスコア TOP10 を確認できます。
- タイトル画面とポーズ画面の「ライブラリ」で、武器・パッシブの説明と Lv ごとの数値、強化・スペシャルの内容を確認できます。武器の詳細では、各パラメータ（ダメージ・攻撃速度・範囲など）の横に影響するパッシブのアイコンが付き、Lv 表にない固定値（回転半径・ノックバックの強さなど）も一覧できます。アイコンをクリックするとそのパッシブの詳細に移ります。

### 武器

武器は Lv1〜5 まで成長し、Lv3 で一段強い強化、最後に Lv6 の「スペシャル」に到達します。

| 武器 | Lv3 の強化 | スペシャル |
|---|---|---|
| ブラスター | マルチロック（近い 2 体を狙う） | 3連ロック・貫通弾 |
| 誘導弾 | 貫通ミサイル | 爆裂弾 |
| 周回シールド | 大型ブレード | 拡大リング（敵弾を反射） |
| 衝撃波 | 減速波 | 電磁シールド |
| 光の翼 | 前方なぎ払い | 常時展開 |
| レーザー | 前後レーザー | 十字レーザー |
| 連鎖電撃 | 連鎖強化（連鎖数 +2） | 放電（連鎖した敵の周囲にも電撃） |
| テセラクト | 二重展開（鋭角の V 字に 2 個放つ） | 共鳴（止まった後も触れた敵にダメージ） |
| 設置機雷 | 炎上（爆発に巻き込んだ敵が燃え、継続ダメージ） | 延焼（燃えている敵が倒れると周りの敵に燃え移る） |
| ドレインリンク | 二重リンク（2 体同時につなぐ） | 連鎖吸収（倒すと近くの敵へ線が移る） |

ドレインリンクは攻撃のたびに HP を 3 消費し、与えたダメージの一部と撃破で HP を回復します（HP が 20 以下のときは攻撃しません）。

パッシブは次の 10 種類です。

| パッシブ | 効果 |
|---|---|
| 攻撃力 | 全武器のダメージが増加 |
| 攻撃速度 | 全武器の攻撃速度が上昇 |
| 移動速度 | 移動速度が増加 |
| 回収範囲 | 経験値と回復アイテムを引き寄せる範囲が拡大 |
| 最大HP | 最大 HP が増加（増えた分だけ回復） |
| 再生 | 毎秒、最大 HP の一定割合を回復 |
| 効果範囲 | 爆発・波・刃などの範囲とレーザーの太さが拡大 |
| 装甲 | 受けるダメージを軽減 |
| 成長 | 獲得経験値が増加 |
| 衝撃 | ノックバックが強くなる |

### 敵

| 敵 | 特徴 |
|---|---|
| 三角形 | 速くて脆い群れ |
| 五角形 | 標準的な敵 |
| 七角形 | 硬くて遅く、ノックバックしにくい |
| 突進型・小（3 つのとげ） | 小さく脆いが、近づくと短い予告ですぐに突進してくる |
| 突進型（3 つのとげ） | 帯で予告してから、自機の先まで一直線に突進する |
| 突進型・大（3 つのとげ） | 硬く大きい。遠くから長い予告のあと、高速で長く突き抜ける |
| 砲台型・小（5 つのとげ） | 小さく脆い。弱い弾をゆっくり撃つ |
| 砲台型（5 つのとげ） | ゆっくり動きながら弾を撃つ |
| 砲台型・大（7 つのとげ） | 硬く遅い。3 方向に広がる弾を撃つ |

敵の一部は遠くから回り込むように近づきます。新しい群れや画面外に離れた敵は、自機の周りで敵が手薄な方角から現れます。

倒した敵は回復アイテム（十字の入った六角形）を落とすことがあります。強い敵ほど落としやすく、触れると HP が 8 回復します。HP が満タンのときはスコア（50）になります。経験値と同じく拾うまで残り、回収範囲で引き寄せられます。

## アートコンセプト

- 敵など自分に不利なもの：暖色系・奇数角形（とげ型も可）
- 自機・経験値・武器など自分に有利なもの：寒色系・偶数角形
- 例外：武器・パッシブのアイコンは見分けやすさを優先し、項目ごとに固有の色・形を使う

このルールは回帰テスト（`tests/unit_tests.gd`）でも検査しています。

## 実行方法

1. [Godot 4.7.2](https://godotengine.org/) をインストールします。
2. Godot のプロジェクトマネージャーでこのフォルダの `project.godot` を開きます。
3. F5（プロジェクトを実行）で起動します。

## 書き出し（Windows）

1. Godot 4.7.2 のエクスポートテンプレートを導入します（エディタの「エクスポートテンプレートの管理」、または公式の `.tpz` を `%APPDATA%\Godot\export_templates\4.7.2.stable` に展開）。
2. 次のスクリプトを実行します。

```powershell
powershell -ExecutionPolicy Bypass -File tools\export\export_windows.ps1
```

`build/windows/` に次が出力され、配布用の `build/NEON_GEOMETRY-<バージョン>-windows.zip` も作られます。

- `NEON GEOMETRY.exe`（PCK 埋め込みの単体実行ファイル）
- `LICENSE`（作者オリジナル部分の MIT License・英語原文）
- `LICENSE.txt`（MIT / OFL / 第三者の切り分けとデータの保存場所）
- `THIRD-PARTY-NOTICES.txt`（エンジン・フォントなどの第三者表記）
- `README.txt`（展開・起動・削除の短い説明）
- `幾何学サバイバー（NEON GEOMETRY）のご紹介.pdf`（同上の案内。原稿は `docs/portfolio/guide.html`）

同じ案内 PDF は、zip と同階層の `build/` にも出力されます（Google Drive などに zip と並べて置く用）。

`tests/` と `tools/` は書き出しに含めません。バージョンは `project.godot` の `config/version` で設定します。
案内 PDF だけ作り直す手順は `docs/README.md` を参照してください。
案内 PDF の印刷には Microsoft Edge が必要です。

## テスト

テストは `tests/` にあり、`tests/run_tests.ps1` で一括実行します。CI（GitHub Actions）も同じスクリプトを使います。

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1                  # 全部（処理時間チェック以外）
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1 -Quick           # ボットを省略
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1 -UpdateBaseline  # ボットの基準値を更新
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1 -Perf            # 処理時間の上限チェックも行う
```

Godot の実行ファイルは `-Godot <パス>` か、環境変数 `GODOT` で指定します（未指定時は `D:\Godot\lib\4.7.2\` を参照）。

| 工程 | 内容 | 問題があったとき |
|---|---|---|
| 構文チェック | 全スクリプト・シーンが読み込めるか（`check_scripts.gd`） | テスト全体を失敗にする |
| 回帰テスト | 表の整合性・アートルール・出現・ランキング・経験値合体（`unit_tests.gd`） | テスト全体を失敗にする |
| スモークテスト | 全武器スペシャルで 60 秒動作（`smoke.gd`） | テスト全体を失敗にする |
| ボット | 3 種のボット × 3 シードを並列実行し、`bot_baseline.txt` と比較（`bot.gd`） | 差分を表示するだけ（失敗にしない） |
| 処理時間 | `-Perf` 指定時のみ。平均フレーム時間が上限を超えていないか | テスト全体を失敗にする |

「テスト全体を失敗にする」工程で問題が出ると、`run_tests.ps1` は 0 以外の終了コードで終わり、CI も失敗になります。

ヘッドレス実行は `--fixed-fps 60` で動かすため、実時間を待たずに進み、同じシードなら同じ結果になります。
`tests/visual/` はウィンドウを開いてスクリーンショットを撮る確認用スクリプトで、CI では実行しません。

バランス調整用のツールもあります（CI では実行しません）。

```powershell
# 武器を固定し、パッシブ 1 種だけを変えて効果を比較（11 条件 × 2 ボット × 6 シード）
powershell -ExecutionPolicy Bypass -File tests\passive_study.ps1
# シード数を増やしてボットを回し、ボットごとのクリア数・平均生存時間を集計
& .\tests\run_tests.ps1 -Policies casual,kite -Seeds (1..10) -LogDir $env:TEMP\bots_a
& .\tests\bot_summary.ps1 $env:TEMP\bots_a
```

## フォルダ構成

```
scenes/
  main.tscn             メインシーン（ルートに game.gd）
  ui/                   UI 画面のシーン（HUD・レベルアップ・リザルト・ポーズ・タイトル・ライブラリ）と共通テーマ ui_theme.tres
scripts/
  game.gd               ゲーム進行・敵の押し合い・UI 画面の切り替え
  ui/                   UI 画面ごとのスクリプト（シーンと同名）
  spawner.gd            敵の出現（画面端・包囲リング）と、離れすぎた敵の呼び戻し
  camera_rig.gd         カメラ（進行方向への先回り・画面の揺れ）
  score_store.gd        ハイスコア TOP10 の記録と保存
  balance.gd            武器・敵・出現率などの調整値
  palette.gd            色定義とアートルール
  player.gd             自機
  enemy.gd              敵（追跡・突進・砲台の挙動）
  enemy_shot.gd         敵弾（周回シールドで反射）
  gem.gd                経験値（段階表示と合体）
  heal_pickup.gd        回復アイテム
  weapons/              各武器（weapon.gd が基底クラス、10 種）
  item_icon.gd          武器・パッシブのアイコン描画
  title_deco.gd         タイトルのネオンロゴ
  background.gd / fx.gd 背景とエフェクト
docs/                   配布用の案内 PDF 原稿・利用条件・README（詳細は docs/README.md）
tests/                  テスト一式と一括実行スクリプト
tools/                  書き出し・案内 PDF 印刷・ライセンス文・効果音と BGM の生成ツール（書き出しには含めない）
.github/workflows/      CI 設定
```

## セーブデータ

ハイスコアは `user://save.cfg`（Windows では `%APPDATA%\NEON GEOMETRY\save.cfg`）に保存されます。
旧名 TestGame 時代の `%APPDATA%\Godot\app_userdata\TestGame\save.cfg` があり、新しい保存先にまだデータがなければ、初回起動時に複写して引き継ぎます。
テストやボットは `nosave` 引数を付けて実行し、セーブデータを書き換えません。
