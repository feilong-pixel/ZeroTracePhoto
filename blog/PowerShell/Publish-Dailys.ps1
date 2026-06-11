param(
    [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$SourceDir = "",
    [string]$OutputDir = "",
    [string]$SiteBaseUrl = "https://zerotracephoto.com/blog"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Join-Path $RootDir "docs\dailys"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RootDir "dailys"
}

$BlogIndexPath = Join-Path $RootDir "index.html"
$SitemapPath = Join-Path $RootDir "sitemap.xml"

function Escape-Html {
    param([AllowNull()][string]$Value)
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function Format-ArticleDateForFooter {
    param([string]$DateText)

    $parsedDate = [datetime]::MinValue
    if ([datetime]::TryParse($DateText, [ref]$parsedDate)) {
        return $parsedDate.ToString("yyyy年MM月dd日")
    }
    return $DateText
}

function Set-ContentIfChanged {
    param(
        [string]$Path,
        [string]$Value
    )

    if (Test-Path -LiteralPath $Path) {
        $currentValue = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
        $currentNormalized = ([regex]::Replace($currentValue, "\r\n?", "`n")).TrimEnd("`r", "`n")
        $nextNormalized = ([regex]::Replace($Value, "\r\n?", "`n")).TrimEnd("`r", "`n")
        if ($currentNormalized -eq $nextNormalized) {
            return
        }
    }

    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Convert-InlineMarkdown {
    param([string]$Text)

    $encoded = Escape-Html $Text
    $encoded = [regex]::Replace($encoded, '!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;([^&]*)&quot;)?\)', {
        param($m)
        $alt = $m.Groups[1].Value
        $src = $m.Groups[2].Value
        $title = $m.Groups[3].Value
        if ($title) {
            return "<img src=""$src"" alt=""$alt"" title=""$title"">"
        }
        return "<img src=""$src"" alt=""$alt"">"
    })
    $encoded = [regex]::Replace($encoded, '\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;([^&]*)&quot;)?\)', {
        param($m)
        $label = $m.Groups[1].Value
        $href = $m.Groups[2].Value
        $title = $m.Groups[3].Value
        if ($title) {
            return "<a href=""$href"" title=""$title"">$label</a>"
        }
        return "<a href=""$href"">$label</a>"
    })
    $encoded = [regex]::Replace($encoded, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $encoded = [regex]::Replace($encoded, '\*([^*]+)\*', '<em>$1</em>')
    $encoded = [regex]::Replace($encoded, '`([^`]+)`', '<code>$1</code>')
    return $encoded
}

function Convert-MarkdownToHtml {
    param([string]$MarkdownText)

    $Lines = [regex]::Split($MarkdownText, "\r?\n")
    $html = New-Object System.Collections.Generic.List[string]
    $paragraph = New-Object System.Collections.Generic.List[string]
    $inCode = $false
    $code = New-Object System.Collections.Generic.List[string]
    $inUl = $false
    $inOl = $false

    function Flush-Paragraph {
        if ($paragraph.Count -gt 0) {
            $joined = ($paragraph -join " ")
            $html.Add("<p>$(Convert-InlineMarkdown $joined)</p>")
            $paragraph.Clear()
        }
    }

    function Close-Lists {
        if ($inUl) {
            $html.Add("</ul>")
            Set-Variable -Name inUl -Value $false -Scope 1
        }
        if ($inOl) {
            $html.Add("</ol>")
            Set-Variable -Name inOl -Value $false -Scope 1
        }
    }

    foreach ($line in $Lines) {
        if ($line -match '^\s*```') {
            Flush-Paragraph
            Close-Lists
            if ($inCode) {
                $html.Add("<pre><code>$(Escape-Html ($code -join "`n"))</code></pre>")
                $code.Clear()
                $inCode = $false
            } else {
                $inCode = $true
            }
            continue
        }

        if ($inCode) {
            $code.Add($line)
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            Flush-Paragraph
            Close-Lists
            continue
        }

        if ($line -match '^(#{1,6})\s+(.+)$') {
            Flush-Paragraph
            Close-Lists
            $level = $Matches[1].Length
            $text = Convert-InlineMarkdown $Matches[2].Trim()
            $html.Add("<h$level>$text</h$level>")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.+)$') {
            Flush-Paragraph
            if ($inOl) {
                $html.Add("</ol>")
                $inOl = $false
            }
            if (-not $inUl) {
                $html.Add("<ul>")
                $inUl = $true
            }
            $html.Add("<li>$(Convert-InlineMarkdown $Matches[1].Trim())</li>")
            continue
        }

        if ($line -match '^\s*\d+\.\s+(.+)$') {
            Flush-Paragraph
            if ($inUl) {
                $html.Add("</ul>")
                $inUl = $false
            }
            if (-not $inOl) {
                $html.Add("<ol>")
                $inOl = $true
            }
            $html.Add("<li>$(Convert-InlineMarkdown $Matches[1].Trim())</li>")
            continue
        }

        if ($line -match '^\s*>\s?(.+)$') {
            Flush-Paragraph
            Close-Lists
            $html.Add("<blockquote>$(Convert-InlineMarkdown $Matches[1].Trim())</blockquote>")
            continue
        }

        $paragraph.Add($line.Trim())
    }

    Flush-Paragraph
    Close-Lists
    if ($inCode) {
        $html.Add("<pre><code>$(Escape-Html ($code -join "`n"))</code></pre>")
    }

    return ($html -join "`n")
}

function Read-MarkdownArticle {
    param([System.IO.FileInfo]$File)

    $raw = Get-Content -Raw -LiteralPath $File.FullName -Encoding UTF8
    $lines = [regex]::Split($raw, "\r?\n")
    $meta = @{}
    $bodyStart = 0

    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq "---") {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq "---") {
                $bodyStart = $i + 1
                break
            }
            if ($lines[$i] -match '^\s*([^:]+):\s*(.+?)\s*$') {
                $meta[$Matches[1].Trim().ToLowerInvariant()] = $Matches[2].Trim().Trim('"')
            }
        }
    }

    $bodyLinesList = New-Object System.Collections.Generic.List[string]
    for ($i = $bodyStart; $i -lt $lines.Count; $i++) {
        $bodyLinesList.Add($lines[$i])
    }
    $bodyLines = [string[]]$bodyLinesList.ToArray()
    $title = $meta["title"]
    if ([string]::IsNullOrWhiteSpace($title)) {
        foreach ($line in $bodyLines) {
            if ($line -match '^#\s+(.+)$') {
                $title = $Matches[1].Trim()
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    }

    for ($i = 0; $i -lt $bodyLines.Count; $i++) {
        if ($bodyLines[$i] -match '^#\s+(.+)$' -and $Matches[1].Trim() -eq $title) {
            $trimmedBody = New-Object System.Collections.Generic.List[string]
            for ($j = 0; $j -lt $bodyLines.Count; $j++) {
                if ($j -ne $i) {
                    $trimmedBody.Add($bodyLines[$j])
                }
            }
            $bodyLines = [string[]]$trimmedBody.ToArray()
            break
        }
        if (-not [string]::IsNullOrWhiteSpace($bodyLines[$i])) {
            break
        }
    }

    $dateText = $meta["date"]
    if ([string]::IsNullOrWhiteSpace($dateText) -and $File.BaseName -match '(\d{4})[-_]?(\d{2})[-_]?(\d{2})') {
        $dateText = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
    }
    if ([string]::IsNullOrWhiteSpace($dateText)) {
        $dateText = $File.LastWriteTime.ToString("yyyy-MM-dd")
    }

    $description = $meta["description"]
    if ([string]::IsNullOrWhiteSpace($description)) {
        $plain = ($bodyLines | Where-Object { $_ -notmatch '^\s*#' -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        if ($plain) {
            $description = $plain.Trim()
            $description = $description.Replace("#", "").Replace("*", "").Replace("_", "").Replace(">", "").Replace("``", "")
        }
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = "网途日志日常记录"
    }

    $slug = $meta["slug"]
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = $File.BaseName
    }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $slug = $slug.Replace($char, "-")
    }
    $slug = $slug.Trim()
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "article"
    }

    $markdownBody = $bodyLines -join "`n"

    [pscustomobject]@{
        Source = $File.FullName
        Slug = $slug
        OutputFile = "$slug.html"
        Title = $title
        Date = $dateText
        Description = $description
        BodyHtml = Convert-MarkdownToHtml -MarkdownText $markdownBody
    }
}

function New-PageHtml {
    param(
        [string]$Title,
        [string]$Description,
        [string]$Breadcrumb,
        [string]$Content,
        [string]$InitialDate,
        [string]$UpdatedDate
    )

    $safeTitle = Escape-Html $Title
    $safeDescription = Escape-Html $Description
    $safeBreadcrumb = Escape-Html $Breadcrumb
    return @"
<!DOCTYPE html>
<html lang="zh-Hans">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<meta name="description" content="$safeDescription">
	<title>$safeTitle - 网途日志</title>
	<link rel="preconnect" href="https://fonts.googleapis.com">
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
	<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@100..900&family=Noto+Serif+SC:wght@200..900&family=Sofia&display=swap" rel="stylesheet">
	<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-9ndCyUaIbzAi2FUVXJi0CjmCapSmO7SnpJef0486qhLnuZ2cdeRhO02iuK6FUUVM" crossorigin="anonymous">
	<link href="../common/css/site.css" rel="stylesheet">
	<style>
		.daily-article { max-width: 820px; margin: 0 auto; line-height: 1.85; }
		.daily-article h1 { margin-bottom: .4rem; text-align: center; }
		.daily-meta { margin-bottom: 1.5rem; text-align: center; color: #6c757d; }
		.daily-article h2, .daily-article h3 { margin-top: 1.8rem; }
		.daily-article img { max-width: 100%; height: auto; }
		.daily-article pre { padding: 1rem; overflow: auto; background: #f8f9fa; border: 1px solid #dee2e6; border-radius: .25rem; }
		.daily-article blockquote { margin: 1rem 0; padding-left: 1rem; color: #495057; border-left: 4px solid #dee2e6; }
		.daily-list { display: grid; gap: .75rem; padding-left: 0; list-style: none; }
		.daily-list a { font-weight: 700; }
	</style>
</head>
<body>
	<div class="container">
		<header class="site-header noto-sans-sc-400">
			<div class="site-header-inner">
				<a href="../" class="d-flex align-items-center mb-md-0 me-md-auto link-body-emphasis text-decoration-none">
					<span class="bi me-2 sofia-regular site-brand-mark">W</span>
					<span class="fs-4">网途日志</span>
				</a>
				<form id="search" method="GET" action="https://www.google.com/search">
					<input type="hidden" name="ie" value="utf-8">
					<input type="hidden" name="oe" value="utf-8">
					<input type="hidden" name="hl" value="zh-CN">
					<input type="hidden" name="lr" value="zh-CN">
					<input type="hidden" name="as_sitesearch" value="zerotracephoto.com/blog">
					<label for="google-search">Search:</label>
					<input id="google-search" type="text" name="q" maxlength="255" value="">
					<input type="submit" name="btnG" value="検索">
					(By <a href="http://www.google.com/">Google</a>)
				</form>
			</div>
		</header>
	</div>

	<div class="container">
		<nav aria-label="breadcrumb">
			<ol class="breadcrumb breadcrumb-chevron">
				<li class="breadcrumb-item"><a class="link-body-emphasis" href="../">主页</a></li>
				<li class="breadcrumb-item"><a class="link-body-emphasis" href="./">日常记录</a></li>
				<li class="breadcrumb-item active" aria-current="page">$safeBreadcrumb</li>
			</ol>
		</nav>
	</div>

	<main class="container daily-article">
$Content
	</main>

	<footer class="container site-footer noto-sans-sc-400">
		<div class="float-end mb-1"><a href="#">返回页首</a></div>
		<div class="mb-0 text-body-secondary">&copy; Copyright (C) 2024 by 网途 <br>初版 : $InitialDate 最終更新 : $UpdatedDate</div>
	</footer>
</body>
</html>
"@
}

function Update-BlogIndex {
    param([array]$Articles)

    $html = Get-Content -Raw -LiteralPath $BlogIndexPath -Encoding UTF8
    $markerStart = "`t`t<!-- DAILY-AUTO-START -->"
    $markerEnd = "`t`t<!-- DAILY-AUTO-END -->"
    $items = if ($Articles.Count -gt 0) {
        ($Articles | Sort-Object Date -Descending | Select-Object -First 12 | ForEach-Object {
            "`t`t`t`t<li><a href=""./dailys/$($_.OutputFile)"">$(Escape-Html $_.Title)</a> <span class=""text-body-secondary"">$($_.Date)</span></li>"
        }) -join "`n"
    } else {
        "`t`t`t`t<li><a href=""./dailys/"">日常记录目录</a></li>"
    }

    $section = @"
$markerStart
		<section class="site-section">
			<h2 class="site-section-title">日常记录</h2>
			<ul class="site-link-list">
$items
			</ul>
		</section>
$markerEnd
"@

    if ($html.Contains("<!-- DAILY-AUTO-START -->")) {
        $pattern = '(?s)\s*<!-- DAILY-AUTO-START -->.*?<!-- DAILY-AUTO-END -->'
        $html = [regex]::Replace($html, $pattern, "`n$section")
    } else {
        $html = [regex]::Replace($html, '(?s)(\s*</div>\s*<!-- FOOTER -->)', "$section`r`n`$1", 1)
    }
    Set-ContentIfChanged -Path $BlogIndexPath -Value $html
}

function Update-Sitemap {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $root = (Resolve-Path $RootDir).Path
    $pages = Get-ChildItem -LiteralPath $RootDir -Filter "*.html" -Recurse |
        Where-Object { $_.FullName -notmatch '\\docs\\' -and $_.FullName -notmatch '\\common\\templates\\' } |
        Sort-Object FullName

    $entries = foreach ($page in $pages) {
        $relative = $page.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        if ($relative -eq "index.html") {
            $loc = "$SiteBaseUrl/"
            $priority = "1.0"
        } else {
            $loc = "$SiteBaseUrl/$relative"
            $priority = if ($relative -like "dailys/*") { "0.7" } else { "0.6" }
        }
        @"
	<url>
		<loc>$loc</loc>
		<lastmod>$today</lastmod>
		<changefreq>weekly</changefreq>
		<priority>$priority</priority>
	</url>
"@
    }

    $sitemap = "<?xml version=""1.0"" encoding=""UTF-8""?>`n<urlset xmlns=""http://www.sitemaps.org/schemas/sitemap/0.9"">`n$($entries -join "`n")`n</urlset>`n"
    Set-ContentIfChanged -Path $SitemapPath -Value $sitemap
}

New-Item -ItemType Directory -Force -Path $SourceDir, $OutputDir | Out-Null

$articles = @(Get-ChildItem -LiteralPath $SourceDir -Filter "*.md" -File | ForEach-Object { Read-MarkdownArticle $_ } | Sort-Object @{ Expression = "Date"; Descending = $true }, Title)
$todayText = (Get-Date).ToString("yyyy年MM月dd日")
$currentArticleFiles = @{}

foreach ($article in $articles) {
    $currentArticleFiles[$article.OutputFile] = $true
    $content = @"
		<h1>$(Escape-Html $article.Title)</h1>
		<div class="daily-meta">$($article.Date)</div>
$($article.BodyHtml)
"@
    $articleDateText = Format-ArticleDateForFooter $article.Date
    $page = New-PageHtml -Title $article.Title -Description $article.Description -Breadcrumb $article.Title -Content $content -InitialDate $articleDateText -UpdatedDate $articleDateText
    Set-ContentIfChanged -Path (Join-Path $OutputDir $article.OutputFile) -Value $page
}

Get-ChildItem -LiteralPath $OutputDir -Filter "*.html" -File |
    Where-Object { $_.Name -ne "index.html" -and -not $currentArticleFiles.ContainsKey($_.Name) } |
    Remove-Item -Force

$listItems = if ($articles.Count -gt 0) {
    ($articles | ForEach-Object {
        "`t`t`t<li><a href=""$($_.OutputFile)"">$(Escape-Html $_.Title)</a><br><span class=""text-body-secondary"">$($_.Date) - $(Escape-Html $_.Description)</span></li>"
    }) -join "`n"
} else {
    "`t`t`t<li class=""text-body-secondary"">还没有发布的日常记录。</li>"
}

$indexContent = @"
		<h1>日常记录</h1>
		<div class="daily-meta">Markdown 自动发布目录</div>
		<ul class="daily-list">
$listItems
		</ul>
"@
$dailyIndex = New-PageHtml -Title "日常记录" -Description "网途日志日常记录目录" -Breadcrumb "日常记录" -Content $indexContent -InitialDate $todayText -UpdatedDate $todayText
Set-ContentIfChanged -Path (Join-Path $OutputDir "index.html") -Value $dailyIndex

Update-BlogIndex -Articles $articles
Update-Sitemap

Write-Host "已发布 $($articles.Count) 篇文章到 $OutputDir"
