const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const contentDir = path.join(root, "content", "schedule");
const archiveDir = path.join(root, "schedule");
const schedulePath = path.join(root, "schedule.html");
const archiveIndexPath = path.join(archiveDir, "index.html");

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

function normalizeYearFileName(name) {
  const match = name.match(/^(\d{4})\.(html|md)$/);
  if (!match) return null;
  return { year: Number(match[1]), ext: match[2] };
}

function renderInlineMarkdown(value, prefix) {
  return escapeHtml(value)
    .replace(/&lt;br&gt;/g, "<br>")
    .replace(/&lt;hr&gt;/g, "<hr>")
    .replace(/\{\{post:(\d+)\|([^}]+)\}\}/g, (_match, id, label) => {
      return `<a href="${prefix}posts/${id}.html" target="_blank">${label}</a>`;
    })
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label, href) => {
      const postMatch = href.match(/^post:(\d+)$/);
      if (postMatch) {
        return `<a href="${prefix}posts/${postMatch[1]}.html" target="_blank">${label}</a>`;
      }
      return `<a href="${href}">${label}</a>`;
    });
}

function splitMarkdownRow(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function isDividerRow(cells) {
  return cells.every((cell) => /^:?-{3,}:?$/.test(cell));
}

function renderMarkdownTable(lines, prefix) {
  const rows = lines.map(splitMarkdownRow).filter((cells) => cells.length > 1);
  if (rows.length < 2 || !isDividerRow(rows[1])) {
    throw new Error("Schedule Markdown must contain a pipe table with a divider row.");
  }

  const header = rows[0];
  const bodyRows = rows.slice(2);
  return `<table border="1" style="font-size: 10pt; line-height: 130%; width: 100%;">
    <thead>
      <tr style="background-color: skyblue;">
        ${header.map((cell) => `<th>${renderInlineMarkdown(cell, prefix)}</th>`).join("\n        ")}
      </tr>
    </thead>
    <tbody>
      ${bodyRows.map((cells) => `<tr>
        ${cells.map((cell) => `<td>${renderInlineMarkdown(cell, prefix)}</td>`).join("\n        ")}
      </tr>`).join("\n      ")}
    </tbody>
  </table>`;
}

function renderScheduleMarkdown(markdown, prefix) {
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  const titleIndex = lines.findIndex((line) => line.startsWith("# "));
  const tableStart = lines.findIndex((line) => line.trim().startsWith("|"));
  if (titleIndex === -1 || tableStart === -1) {
    throw new Error("Schedule Markdown must include a '# title' and a pipe table.");
  }

  const title = lines[titleIndex].replace(/^#\s+/, "").trim();
  const tableLines = [];
  for (let i = tableStart; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line.startsWith("|")) break;
    tableLines.push(line);
  }

  return `<section class="content-block schedule-section schedule-feature">
  <h2>${renderInlineMarkdown(title, prefix)}</h2>
  ${renderMarkdownTable(tableLines, prefix)}
</section>`;
}

function renderScheduleContent(entry, prefix = "") {
  const content = read(entry.file).trim();
  if (entry.ext === "md") {
    return renderScheduleMarkdown(content, prefix);
  }
  return content;
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

function shell({ title, description, prefix = "", body }) {
  return `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escapeHtml(description)}">
  <title>${escapeHtml(title)} | 高洲ホープスバドミントンクラブ</title>
  <link rel="stylesheet" href="${prefix}assets/styles.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="${prefix}index.html">高洲ホープスバドミントンクラブ</a>
    <nav>${nav("schedule", prefix)}</nav>
  </header>
  <main class="page simple-page schedule-page">
${body}
  </main>
  <footer class="site-footer">
    <p>Copyright(c) 2019 Takasu HOPES All Rights Reserved.</p>
  </footer>
</body>
</html>`;
}

function yearFiles() {
  if (!fs.existsSync(contentDir)) return [];
  const byYear = new Map();
  for (const name of fs.readdirSync(contentDir)) {
    const parsed = normalizeYearFileName(name);
    if (!parsed) continue;
    const existing = byYear.get(parsed.year);
    if (!existing || parsed.ext === "md") {
      byYear.set(parsed.year, {
        year: parsed.year,
        ext: parsed.ext,
        file: path.join(contentDir, name),
      });
    }
  }
  return Array.from(byYear.values())
    .sort((a, b) => b.year - a.year);
}

function archiveLinks(years, currentYear, prefix = "") {
  const links = years
    .filter(({ year }) => year !== currentYear)
    .map(({ year }) => `<a href="${prefix}schedule/${year}.html">${year}年の活動予定</a>`)
    .join("\n        ");

  if (!links) return "";
  return `<section class="content-block schedule-archive">
      <h2>過去の活動予定</h2>
      <div class="archive-links">
        ${links}
      </div>
    </section>`;
}

function main() {
  const years = yearFiles();
  if (!years.length) {
    throw new Error(`No schedule fragments found in ${contentDir}`);
  }

  const latest = years[0];
  const latestHtml = renderScheduleContent(latest);
  write(schedulePath, shell({
    title: "活動予定",
    description: "高洲ホープスバドミントンクラブの活動予定",
    body: `    <h1>🌻活動予定</h1>
    <p class="lead">${latest.year}年の活動予定を掲載しています。</p>
    ${latestHtml}
    ${archiveLinks(years, latest.year)}`,
  }));

  const archiveIndexLinks = years
    .map(({ year }) => `<a href="${year}.html">${year}年の活動予定</a>`)
    .join("\n        ");
  write(archiveIndexPath, shell({
    title: "活動予定 年別一覧",
    description: "高洲ホープスバドミントンクラブの活動予定の年別一覧",
    prefix: "../",
    body: `    <h1>活動予定 年別一覧</h1>
    <section class="content-block schedule-archive">
      <h2>年別一覧</h2>
      <div class="archive-links">
        ${archiveIndexLinks}
      </div>
    </section>
    <p class="back-link"><a href="../schedule.html">最新の活動予定へ戻る</a></p>`,
  }));

  for (const { year, file } of years) {
    const content = renderScheduleContent({ year, file, ext: path.extname(file).slice(1) }, "../");
    write(path.join(archiveDir, `${year}.html`), shell({
      title: `${year}年 活動予定`,
      description: `高洲ホープスバドミントンクラブの${year}年活動予定`,
      prefix: "../",
      body: `    <h1>${year}年 活動予定</h1>
    ${content}
    <p class="back-link"><a href="../schedule.html">最新の活動予定へ戻る</a></p>
    <p class="back-link"><a href="index.html">年別一覧を見る</a></p>`,
    }));
  }

  console.log(JSON.stringify({
    latestYear: latest.year,
    archiveYears: years.length,
  }, null, 2));
}

main();
