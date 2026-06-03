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
- `schedule.html`: activity schedule
- `recruit.html`: recruitment page
- `access.html`: practice schedule, location, and map
- `posts.html`: article index
- `videos.html`: video index
- `posts/`: 112 article pages
- `videos/`: generated video pages
- `assets/`: CSS and locally referenced images
- `content/posts/`: Markdown source for new posts
- `content/videos/`: Markdown source for videos
- `docs/publishing.md`: new-post publishing workflow
- `build.ps1`: rebuild post/video pages, indexes, and home-page recent posts

The previous HTTrack/Ameba runtime files were removed. This site does not depend on Ameba's JavaScript runtime, Google Analytics, or Instagram embed scripts. The access page embeds Google Maps for the practice location.

## Publish New Posts

Write new articles in `content/posts/*.md`, then run:

```powershell
.\build.ps1
```

See `docs/publishing.md` for the full workflow.

The same document also covers how to hide or delete posts.
