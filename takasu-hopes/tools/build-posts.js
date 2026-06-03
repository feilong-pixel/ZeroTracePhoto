const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const contentDir = path.join(root, "content", "posts");
const videoContentDir = path.join(root, "content", "videos");
const postsDir = path.join(root, "posts");
const videosDir = path.join(root, "videos");
const indexPath = path.join(root, "index.html");
const postsIndexPath = path.join(root, "posts.html");
const videosIndexPath = path.join(root, "videos.html");
const includeDrafts = process.argv.includes("--include-drafts");

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content, "utf8");
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function stripTags(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<figure class="video-embed">[\s\S]*?<\/figure>/gi, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseFrontMatter(markdown, file) {
  if (!markdown.startsWith("---\n")) {
    throw new Error(`${file} is missing front matter`);
  }
  const end = markdown.indexOf("\n---", 4);
  if (end === -1) {
    throw new Error(`${file} has invalid front matter`);
  }

  const raw = markdown.slice(4, end).trim();
  const body = markdown.slice(end + 4).trim();
  const data = {};

  for (const line of raw.split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (value === "true") value = true;
    if (value === "false") value = false;
    data[match[1]] = value;
  }

  if (!data.title) throw new Error(`${file} is missing title`);
  if (!data.date) throw new Error(`${file} is missing date`);

  return { data, body };
}

function slugFromMarkdown(file) {
  return path.basename(file, ".md").replace(/^\d{4}-\d{2}-\d{2}-/, "");
}

function normalizeRootImage(image) {
  if (!image) return "";
  return String(image).replace(/^\/+/, "");
}

function rootPathToPostPath(image) {
  const clean = normalizeRootImage(image);
  return clean ? `../${clean}` : "";
}

function renderInline(text) {
  let value = escapeHtml(text);
  value = value.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_m, alt, src) => {
    const cleanSrc = normalizeRootImage(src);
    const finalSrc = cleanSrc.startsWith("assets/") ? `../${cleanSrc}` : cleanSrc;
    return `<img src="${escapeHtml(finalSrc)}" alt="${escapeHtml(alt)}">`;
  });
  value = value.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_m, label, href) => {
    return `<a href="${escapeHtml(href)}">${escapeHtml(label)}</a>`;
  });
  value = value.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  value = value.replace(/`([^`]+)`/g, "<code>$1</code>");
  return value;
}

function youtubeEmbedFromLine(line) {
  const match = line.trim().match(/^\{%\s*youtube\s+(\S+)(?:\s+(.+?))?\s*%\}$/i);
  if (!match) return "";

  const videoId = youtubeVideoId(match[1]);
  if (!videoId) return "";

  const title = match[2] ? match[2].replace(/^["']|["']$/g, "") : "YouTube video player";
  const watchUrl = `https://www.youtube.com/watch?v=${videoId}`;
  return `<figure class="video-embed">
  <div class="video-frame">
    <iframe src="https://www.youtube.com/embed/${escapeHtml(videoId)}" title="${escapeHtml(title)}" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
  </div>
  <figcaption><a href="${escapeHtml(watchUrl)}" target="_blank" rel="noopener">YouTubeで見る</a></figcaption>
</figure>`;
}

function youtubeVideoId(url) {
  const value = String(url).trim();
  const direct = value.match(/^[A-Za-z0-9_-]{11}$/);
  if (direct) return value;

  try {
    const parsed = new URL(value);
    if (parsed.hostname === "youtu.be") {
      return parsed.pathname.split("/").filter(Boolean)[0] || "";
    }
    if (parsed.hostname.endsWith("youtube.com")) {
      if (parsed.pathname === "/watch") return parsed.searchParams.get("v") || "";
      const embed = parsed.pathname.match(/^\/embed\/([A-Za-z0-9_-]{11})/);
      if (embed) return embed[1];
    }
  } catch (_error) {
    return "";
  }

  return "";
}

function markdownToHtml(markdown) {
  const lines = markdown.split(/\r?\n/);
  const out = [];
  let paragraph = [];
  let inFence = false;
  let fence = [];

  function flushParagraph() {
    if (!paragraph.length) return;
    out.push(`<p>${renderInline(paragraph.join(" "))}</p>`);
    paragraph = [];
  }

  for (const line of lines) {
    if (line.trim().startsWith("```")) {
      if (inFence) {
        out.push(`<pre><code>${escapeHtml(fence.join("\n"))}</code></pre>`);
        fence = [];
        inFence = false;
      } else {
        flushParagraph();
        inFence = true;
      }
      continue;
    }

    if (inFence) {
      fence.push(line);
      continue;
    }

    if (!line.trim()) {
      flushParagraph();
      continue;
    }

    const youtubeEmbed = youtubeEmbedFromLine(line);
    if (youtubeEmbed) {
      flushParagraph();
      out.push(youtubeEmbed);
      continue;
    }

    const h2 = line.match(/^##\s+(.+)$/);
    if (h2) {
      flushParagraph();
      out.push(`<h2>${renderInline(h2[1])}</h2>`);
      continue;
    }

    const h3 = line.match(/^###\s+(.+)$/);
    if (h3) {
      flushParagraph();
      out.push(`<h3>${renderInline(h3[1])}</h3>`);
      continue;
    }

    paragraph.push(line.trim());
  }

  flushParagraph();
  return out.join("\n");
}

function formatDate(date) {
  const value = String(date).trim();
  const parsed = parsePostDate(value);
  if (!Number.isNaN(parsed.getTime())) {
    const pad = (num) => String(num).padStart(2, "0");
    return `${parsed.getFullYear()}.${pad(parsed.getMonth() + 1)}.${pad(parsed.getDate())} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
  }
  return value.replace("T", " ").replace(/:00$/, "");
}

function parsePostDate(date) {
  const value = String(date).trim();
  const normalized = value
    .replace(/^(\d{4})\.(\d{2})\.(\d{2})/, "$1-$2-$3")
    .replace(" ", "T");
  return new Date(normalized);
}

function sortDateValue(post) {
  const parsed = parsePostDate(post.date);
  return Number.isNaN(parsed.getTime()) ? 0 : parsed.getTime();
}

function nav(active, prefix = "") {
  const items = [
    ["index.html", "ホーム", "home"],
    ["schedule.html", "活動予定", "schedule"],
    ["recruit.html", "新規部員の募集", "recruit"],
    ["access.html", "アクセス", "access"],
    ["posts.html", "記事一覧", "posts"],
    ["videos.html", "動画一覧", "videos"],
  ];
  return items.map(([href, label, key]) => {
    const className = key === active ? ` class="active"` : "";
    return `<a${className} href="${prefix}${href}">${label}</a>`;
  }).join("");
}

function articleShell(post, options = {}) {
  const image = rootPathToPostPath(post.image);
  const body = post.html;
  const pageClass = body.includes('class="video-embed"') ? "article-page article-page-wide" : "article-page";
  const active = options.active || "posts";
  const backHref = options.backHref || "../posts.html";
  const backLabel = options.backLabel || "記事一覧へ戻る";
  return `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escapeHtml(post.description)}">
  <title>${escapeHtml(post.title)} | 高洲ホープスバドミントンクラブ</title>
  <link rel="stylesheet" href="../assets/styles.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="../index.html">高洲ホープスバドミントンクラブ</a>
    <nav>${nav(active, "../")}</nav>
  </header>
  <main class="page ${pageClass}">
    <p class="date">${escapeHtml(formatDate(post.date))}</p>
    <h1>${escapeHtml(post.title)}</h1>
    ${image ? `<img class="hero-image" src="${escapeHtml(image)}" alt="">` : ""}
    <article class="article-body">${body}</article>
    <p class="back-link"><a href="${escapeHtml(backHref)}">${escapeHtml(backLabel)}</a></p>
  </main>
  <footer class="site-footer">
    <p>Copyright(c) 2019 Takasu HOPES All Rights Reserved.</p>
  </footer>
</body>
</html>`;
}

function parseExistingPost(file) {
  const html = read(file);
  const title = (html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i) || [null, "Untitled"])[1].replace(/<[^>]+>/g, "").trim();
  const date = (html.match(/<p class="date">([\s\S]*?)<\/p>/i) || [null, ""])[1].replace(/<[^>]+>/g, "").trim();
  const imageMatch = html.match(/<img class="hero-image" src="\.\.\/([^"]+)"/i);
  const bodyMatch = html.match(/<article class="article-body">([\s\S]*?)<\/article>/i);
  const bodyText = bodyMatch ? stripTags(bodyMatch[1]) : "";
  const id = path.basename(file, ".html");

  return {
    id,
    title,
    date,
    image: imageMatch ? imageMatch[1] : "",
    description: bodyText.slice(0, 180),
    url: `posts/${id}.html`,
  };
}

function postCard(post, heading = "h2") {
  const image = normalizeRootImage(post.image);
  return `    <article class="post-card">
      ${image ? `<img src="${escapeHtml(image)}" alt="">` : ""}
      <div>
        <p class="date">${escapeHtml(formatDate(post.date))}</p>
        <${heading}><a href="${escapeHtml(post.url)}">${escapeHtml(post.title)}</a></${heading}>
        <p>${escapeHtml(post.description)}...</p>
      </div>
    </article>`;
}

function replaceBetweenMarkers(html, start, end, replacement) {
  const pattern = new RegExp(`${start}[\\s\\S]*?${end}`);
  if (!pattern.test(html)) {
    throw new Error(`Missing marker pair ${start} / ${end}`);
  }
  return html.replace(pattern, `${start}\n${replacement}\n${end}`);
}

function ensureMarkers() {
  let index = read(indexPath);
  if (!index.includes("<!-- POSTS:START -->")) {
    index = index.replace(
      /(<div class="post-grid">)([\s\S]*?)(<\/div>\s*<\/section>)/,
      `$1\n<!-- POSTS:START -->$2<!-- POSTS:END -->\n$3`
    );
    write(indexPath, index);
  }

  let postsIndex = read(postsIndexPath);
  if (!postsIndex.includes("<!-- POSTS:START -->")) {
    postsIndex = postsIndex.replace(
      /(<div class="post-list">)([\s\S]*?)(<\/div>\s*<\/main>)/,
      `$1\n<!-- POSTS:START -->$2<!-- POSTS:END -->\n$3`
    );
    write(postsIndexPath, postsIndex);
  }

  if (!fs.existsSync(videosIndexPath)) {
    write(videosIndexPath, `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="高洲ホープスバドミントンクラブの動画一覧">
  <title>動画一覧 | 高洲ホープスバドミントンクラブ</title>
  <link rel="stylesheet" href="assets/styles.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="index.html">高洲ホープスバドミントンクラブ</a>
    <nav>${nav("videos")}</nav>
  </header>
  <main class="page">
    <h1>動画一覧</h1>
    <div class="video-list">
<!-- VIDEOS:START -->
<!-- VIDEOS:END -->
    </div>
  </main>
  <footer class="site-footer">
    <p>Copyright(c) 2019 Takasu HOPES All Rights Reserved.</p>
  </footer>
</body>
</html>`);
  }

  let videosIndex = read(videosIndexPath);
  if (!videosIndex.includes("<!-- VIDEOS:START -->")) {
    videosIndex = videosIndex.replace(
      /(<div class="video-list">)([\s\S]*?)(<\/div>\s*<\/main>)/,
      `$1\n<!-- VIDEOS:START -->$2<!-- VIDEOS:END -->\n$3`
    );
    write(videosIndexPath, videosIndex);
  }
}

function readMarkdownCollection(sourceDir, outputDir, urlPrefix, shellOptions) {
  const items = [];
  let skippedDrafts = 0;
  fs.mkdirSync(outputDir, { recursive: true });

  if (!fs.existsSync(sourceDir)) {
    return { items, skippedDrafts };
  }

  for (const name of fs.readdirSync(sourceDir).filter((item) => item.endsWith(".md"))) {
    const file = path.join(sourceDir, name);
    const { data, body } = parseFrontMatter(read(file), file);
    const slug = slugFromMarkdown(name);
    if (data.draft && !includeDrafts) {
      skippedDrafts += 1;
      const draftOutput = path.join(outputDir, `${slug}.html`);
      if (fs.existsSync(draftOutput)) {
        fs.rmSync(draftOutput);
      }
      continue;
    }

    const html = markdownToHtml(body);
    const post = {
      id: slug,
      title: data.title,
      date: data.date,
      image: normalizeRootImage(data.image || ""),
      description: stripTags(html).slice(0, 180),
      html,
      url: `${urlPrefix}/${slug}.html`,
    };
    items.push(post);
    write(path.join(outputDir, `${slug}.html`), articleShell(post, shellOptions));
  }

  return { items, skippedDrafts };
}

function videoCard(video) {
  return `    <article class="video-card">
      <div>
        <p class="date">${escapeHtml(formatDate(video.date))}</p>
        <h2><a href="${escapeHtml(video.url)}">${escapeHtml(video.title)}</a></h2>
        <p>${escapeHtml(video.description)}...</p>
      </div>
      <a class="button light-button" href="${escapeHtml(video.url)}">動画を見る</a>
    </article>`;
}

function main() {
  ensureMarkers();

  const postsResult = readMarkdownCollection(contentDir, postsDir, "posts", {
    active: "posts",
    backHref: "../posts.html",
    backLabel: "記事一覧へ戻る",
  });
  const markdownPosts = postsResult.items;

  const generatedIds = new Set(markdownPosts.map((post) => post.id));
  const existingPosts = fs.readdirSync(postsDir)
    .filter((name) => name.endsWith(".html"))
    .map((name) => path.join(postsDir, name))
    .filter((file) => !generatedIds.has(path.basename(file, ".html")))
    .map(parseExistingPost);

  const allPosts = [...markdownPosts, ...existingPosts]
    .sort((a, b) => sortDateValue(b) - sortDateValue(a));

  const postsCards = allPosts.map((post) => postCard(post, "h2")).join("\n");
  let postsIndex = read(postsIndexPath);
  postsIndex = replaceBetweenMarkers(postsIndex, "<!-- POSTS:START -->", "<!-- POSTS:END -->", postsCards);
  write(postsIndexPath, postsIndex);

  const homeCards = allPosts.slice(0, 6).map((post) => postCard(post, "h3")).join("\n");
  let index = read(indexPath);
  index = replaceBetweenMarkers(index, "<!-- POSTS:START -->", "<!-- POSTS:END -->", homeCards);
  write(indexPath, index);

  const videosResult = readMarkdownCollection(videoContentDir, videosDir, "videos", {
    active: "videos",
    backHref: "../videos.html",
    backLabel: "動画一覧へ戻る",
  });
  const videos = videosResult.items.sort((a, b) => sortDateValue(b) - sortDateValue(a));
  let videosIndex = read(videosIndexPath);
  videosIndex = replaceBetweenMarkers(videosIndex, "<!-- VIDEOS:START -->", "<!-- VIDEOS:END -->", videos.map(videoCard).join("\n"));
  write(videosIndexPath, videosIndex);

  console.log(JSON.stringify({
    markdownPosts: markdownPosts.length,
    skippedDrafts: postsResult.skippedDrafts,
    markdownVideos: videos.length,
    skippedVideoDrafts: videosResult.skippedDrafts,
    totalPosts: allPosts.length,
    includeDrafts,
  }, null, 2));
}

main();
