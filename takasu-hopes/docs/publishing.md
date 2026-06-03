# 新しい記事の公開手順

このサイトは静的 HTML サイトです。新しい記事は Markdown で書き、ビルドスクリプトで HTML に変換します。

## 1. 記事を書く

`content/posts/` に Markdown ファイルを作成します。

ファイル名の例:

```text
content/posts/2026-06-02-tournament-report.md
```

記事の形式:

```md
---
title: "🌸大会結果のお知らせ"
date: "2026-06-02 10:00"
image: "assets/images/example.jpg"
draft: false
---

本文を書きます。

段落は空行で区切ります。
```

動画は記事とは分けて、`content/videos/` に Markdown ファイルを作成します。

ファイル名の例:

```text
content/videos/2026-06-03-badminton-video-example.md
```

動画ページの形式:

```md
---
title: "バドミントン試合動画の紹介"
date: "2026-06-03 10:00"
draft: false
---

動画の紹介文を書きます。

{% youtube https://www.youtube.com/watch?v=VIDEO_ID "動画タイトル" %}
```

## 2. 画像を置く

記事のメイン画像や本文画像は `assets/images/` に置きます。

Front matter の `image` には、サイトルートからのパスを書きます。

```md
image: "assets/images/example.jpg"
```

本文中の画像も同じ形式で書けます。

```md
![写真の説明](assets/images/example.jpg)
```

## 3. YouTube 動画を入れる

動画ページの本文中に YouTube 動画を入れたい場合は、動画を置きたい場所に次のように書きます。

```md
{% youtube https://www.youtube.com/watch?v=VIDEO_ID "動画タイトル" %}
```

動画タイトルは省略できます。

```md
{% youtube https://youtu.be/VIDEO_ID %}
```

ビルドすると、動画ページではレスポンシブな動画プレーヤーとして表示されます。プレーヤーの下には YouTube で開くための通常リンクも自動で表示されます。

## 4. 下書きと公開

下書きにしたい場合:

```md
draft: true
```

公開したい場合:

```md
draft: false
```

または `draft` 行を削除しても公開扱いになります。

## 5. HTML を生成する

通常の公開ビルド:

```powershell
.\build.ps1
```

下書きも含めて確認したい場合:

```powershell
.\build.ps1 -IncludeDrafts
```

ビルドすると次のファイルが更新されます。

- `posts/<slug>.html`
- `videos/<slug>.html`
- `posts.html`
- `videos.html`
- `index.html` の最新記事セクション

既存の古い HTML 記事も読み取り、記事一覧に残します。動画は `content/videos/` から生成され、記事一覧には入りません。

## 6. ローカル確認

```powershell
.\serve.ps1
```

ブラウザで開きます。

```text
http://localhost:8080/
```

## 運用メモ

- 新規記事はできるだけ Markdown で追加します。
- 新規動画は `content/videos/` に Markdown で追加します。
- 既存の `posts/*.html` はそのまま残します。
- 記事一覧と首页の最新記事は、ビルド時に日付順で自動更新されます。
- 動画一覧は `content/videos/` から生成され、記事一覧とは分かれます。
- サンプル記事 `content/posts/2026-06-02-sample.md` は `draft: true` なので通常ビルドには出ません。

動画を入れる場合の例:

```md
---
title: "大会後のふりかえり動画"
date: "2026-06-10 18:00"
draft: false
---

今日は大会後の感想を動画でまとめました。

{% youtube https://www.youtube.com/watch?v=VIDEO_ID "大会後のふりかえり動画" %}
```

## 記事を非表示・削除する

### Markdown で追加した記事を一時的に非表示にする

Markdown ファイルの `draft` を `true` にします。動画の場合も同じです。

```md
---
title: "🌸大会結果のお知らせ"
date: "2026-06-02 10:00"
image: "assets/images/example.jpg"
draft: true
---
```

その後、通常ビルドを実行します。

```powershell
.\build.ps1
```

この場合、記事は首页と `posts.html` から消えます。動画の場合は `videos.html` から消えます。過去に下書きプレビューで生成された `posts/<slug>.html` や `videos/<slug>.html` も通常ビルド時に削除されます。

### Markdown で追加した記事を完全に削除する

Markdown ファイルを削除します。動画の場合は `content/videos/` の Markdown ファイルを削除します。

```powershell
Remove-Item content\posts\2026-06-02-tournament-report.md
.\build.ps1
```

生成済み HTML が残っている場合は、対応する `posts/<slug>.html` も削除します。

```powershell
Remove-Item posts\tournament-report.html
.\build.ps1
```

動画の場合:

```powershell
Remove-Item videos\badminton-video-example.html
.\build.ps1
```

### 既存の古い HTML 記事を削除する

既存記事は `posts/*.html` に直接あります。削除したい HTML ファイルを消してからビルドします。

```powershell
Remove-Item posts\58866826.html
.\build.ps1
```

首页には最新 6 件が表示されます。削除した記事が首页に出ていた場合は、次に新しい記事が自動で補充されます。
