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
  return fs.readdirSync(contentDir)
    .map((name) => {
      const match = name.match(/^(\d{4})\.html$/);
      return match ? { year: Number(match[1]), file: path.join(contentDir, name) } : null;
    })
    .filter(Boolean)
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
  const latestHtml = read(latest.file).trim();
  write(schedulePath, shell({
    title: "活動予定",
    description: "高洲ホープスバドミントンクラブの活動予定",
    body: `    <h1>活動予定</h1>
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
    const content = read(file).trim();
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
