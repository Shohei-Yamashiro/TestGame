# 配布文書

ポートフォリオとして zip で配るときの案内と利用条件です。
ゲーム本体の遊び方はアプリ内（タイトル・ライブラリ）にあり、案内 PDF は展開と削除を中心にした最小限構成です。

| パス | 内容 |
|---|---|
| `portfolio/guide.html` | 案内 PDF の原稿（Edge で印刷） |
| `portfolio/pdf-filename.txt` | zip に入れる PDF の日本語ファイル名 |
| `distribution/LICENSE.txt` | 利用条件 |
| `distribution/README.txt` | 配布用の短い説明 |
| （リポジトリ直下）`THIRD-PARTY-NOTICES.txt` | Godot とフォントなどの第三者表記（生成物） |

## 作り方

```powershell
# 案内 PDF だけ作る
powershell -ExecutionPolicy Bypass -File tools\docs\build-docs.ps1 `
  -Html docs\portfolio\guide.html -Pdf build\NEON_GEOMETRY-guide.pdf

# ページ画像で確認する
powershell -ExecutionPolicy Bypass -File tools\docs\pdf2png.ps1 `
  -Pdf build\NEON_GEOMETRY-guide.pdf -OutDir build\guide-pages

# ゲーム本体と文書をまとめて zip にする
powershell -ExecutionPolicy Bypass -File tools\export\export_windows.ps1
```

`THIRD-PARTY-NOTICES.txt` を更新するとき：

```powershell
& "<Godot console exe>" --headless --path . -s res://tools/licenses/generate_notices.gd
```
