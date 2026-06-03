# 高洲ホープスバドミントンクラブ static site

This is a clean static HTML version of the Ameba Ownd site.

## Preview

```powershell
.\serve.ps1
```

Open:

http://localhost:8080/

## Contents

- `index.html`: home page
- `schedule.html`: latest activity schedule
- `recruit.html`: recruitment page
- `access.html`: practice schedule, location, and map
- `posts.html`: article index
- `videos.html`: video index
- `posts/`: 112 article pages
- `schedule/`: generated yearly schedule pages
- `videos/`: generated video pages
- `assets/`: CSS and locally referenced images
- `content/posts/`: Markdown source for new posts
- `content/schedule/`: schedule source files
- `content/videos/`: Markdown source for videos
- `docs/publishing.md`: new-post publishing workflow
- `build.ps1`: rebuild generated pages and indexes

The previous HTTrack/Ameba runtime files were removed. This site does not depend on Ameba's JavaScript runtime, Google Analytics, or Instagram embed scripts. The access page embeds Google Maps for the practice location.

## Build

Run this after changing Markdown content or schedule sources:

```powershell
.\build.ps1
```

This rebuilds:

- article pages from `content/posts/*.md`
- video pages from `content/videos/*.md`
- `posts.html`, `videos.html`, and the home-page recent lists
- `schedule.html`, `schedule/index.html`, and `schedule/YYYY.html`

## Publish New Posts

Write new articles in `content/posts/*.md`.

Example:

```markdown
---
title: "大会レポート"
date: "2026-06-01 10:00"
image: "assets/images/example.jpg"
---

本文を Markdown で書きます。
```

Then run `.\build.ps1`.

See `docs/publishing.md` for the full workflow. The same document also covers how to hide or delete posts.

## Maintain Activity Schedules

Old yearly schedules keep their original HTML fragments so the historical look remains intact:

```text
content/schedule/2019.html
content/schedule/2020.html
...
content/schedule/2025.html
```

New schedules can be maintained as Markdown. For example, 2026 uses:

```text
content/schedule/2026.md
```

The build script prefers `YYYY.md` over `YYYY.html` when both exist for the same year. This lets newer years use a simpler editing flow while older pages keep their original table style.

Example schedule Markdown:

```markdown
---
style: green
---

# 🌸令和8年度(2026年度)行事

| 開催日 | 曜日 | 行事名 | 会場 | 備考 |
|---|---|---|---|---|
| 2026年5月23日～24日 | 土日 | 第42回若葉カップ [👉BLOGへ](post:58866826) | 香取市・香取市民体育館 | [結果](https://example.com/result.pdf) |
```

Supported table helpers:

- `[結果](https://example.com/result.pdf)`: external links
- `[👉BLOGへ](post:58866826)`: link to a local article page
- `<br>` and `<hr>` inside a table cell for multi-line schedule entries

Available Markdown schedule styles:

- `green`
- `blue`
- `yellow`
- `classic`

To add a new style, copy one of the `.schedule-style-*` blocks in `assets/styles.css`, change the CSS variables, and use the new name in the Markdown front matter.
