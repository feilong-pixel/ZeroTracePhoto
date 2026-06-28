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
    $code = New-Object System.Collections.Generic.List[string]
    $blockquoteLines = New-Object System.Collections.Generic.List[string]

    $state = @{
        inCode = $false
        inUl = $false
        inOl = $false
        inBlockquote = $false
        inTable = $false
        hasPendingCharacter = $false
        pendingCharacter = ""
        pendingParenthetical = ""
    }
    $tableAlignments = New-Object System.Collections.Generic.List[string]

    function Flush-Paragraph {
        if ($paragraph.Count -gt 0) {
            $joined = ($paragraph -join " ")
            if ($joined -match '^\s*(?:\*+)?(注[：:])\s*(.+)$') {
                $label = $Matches[1]
                $content = $Matches[2]
                $html.Add("<p class=`"footnote`"><strong>$label</strong>$(Convert-InlineMarkdown $content)</p>")
            } else {
                $html.Add("<p>$(Convert-InlineMarkdown $joined)</p>")
            }
            $paragraph.Clear()
        }
    }

    function Close-Lists {
        if ($state.inUl) {
            $html.Add("</ul>")
            $state.inUl = $false
        }
        if ($state.inOl) {
            $html.Add("</ol>")
            $state.inOl = $false
        }
    }

    function Close-Table {
        if ($state.inTable) {
            $html.Add("</tbody>")
            $html.Add("</table>")
            $state.inTable = $false
        }
    }

    function Flush-PendingCharacter {
        if ($state.hasPendingCharacter) {
            $text = "<strong>$($state.pendingCharacter)</strong>"
            if ($state.pendingParenthetical) {
                $text += " $(Convert-InlineMarkdown $state.pendingParenthetical)"
            }
            $text += "："
            $html.Add("<p>$text</p>")
            $state.hasPendingCharacter = $false
        }
    }

    function Flush-Blockquote {
        if ($state.inBlockquote) {
            if ($blockquoteLines.Count -gt 0) {
                # Check if first line is a callout identifier
                $firstLine = $blockquoteLines[0].Trim()
                if ($firstLine -match '^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$') {
                    $type = $Matches[1].ToUpper()
                    $blockquoteLines.RemoveAt(0)
                    $innerMarkdown = $blockquoteLines -join "`n"
                    # Render inner markdown recursively
                    $innerHtml = Convert-MarkdownToHtml -MarkdownText $innerMarkdown
                    
                    # Icons and Titles mapping
                    $titleMap = @{
                        "NOTE" = "提示"
                        "TIP" = "建议"
                        "IMPORTANT" = "重要"
                        "WARNING" = "警告"
                        "CAUTION" = "注意"
                    }
                    $svgMap = @{
                        "NOTE" = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" class="me-2"><path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-3a1 1 0 1 0 0-2 1 1 0 0 0 0 2Zm1.5 7a.5.5 0 0 0 0-1H9V7a.5.5 0 0 0-.5-.5h-2a.5.5 0 0 0 0 1h1V11H7a.5.5 0 0 0 0 1h2.5Z"></path></svg>'
                        "TIP" = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" class="me-2"><path d="M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.426 1.913 1.12 2.518.502.438.88 1.054.88 1.732v.25a.75.75 0 0 0 .75.75h2.5a.75.75 0 0 0 .75-.75v-.25c0-.678.378-1.294.88-1.732.694-.605 1.12-1.534 1.12-2.518 0-2.06-1.637-3.75-4-3.75ZM5.97 7.03A3.75 3.75 0 0 1 5.5 5.25c0-1.27 1.01-2.25 2.5-2.25s2.5.98 2.5 2.25c0 .628-.19 1.218-.47 1.78a2.25 2.25 0 0 0-.51.72H6.98a2.25 2.25 0 0 0-.51-.72ZM6.25 12h3.5a.75.75 0 0 1 0 1.5h-3.5a.75.75 0 0 1 0-1.5Zm1 2.5h1.5a.25.25 0 0 1 0 .5h-1.5a.25.25 0 0 1 0-.5Z"></path></svg>'
                        "IMPORTANT" = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" class="me-2"><path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-3a.75.75 0 0 0-.75.75v3.5a.75.75 0 0 0 1.5 0v-3.5A.75.75 0 0 0 8 5Zm0 6a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z"></path></svg>'
                        "WARNING" = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" class="me-2"><path d="M6.457 1.047c.659-1.203 2.427-1.203 3.086 0l6.03 11c.629 1.147-.202 2.533-1.543 2.533H1.97C.628 14.58-.203 13.194.426 12.047l6.03-11ZM8 4.75a.75.75 0 0 0-.75.75v3.5a.75.75 0 0 0 1.5 0v-3.5A.75.75 0 0 0 8 4.75Zm0 7.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z"></path></svg>'
                        "CAUTION" = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" class="me-2"><path d="M4.47.22A.75.75 0 0 1 5 0h6a.75.75 0 0 1 .53.22l4.25 4.25c.141.14.22.33.22.53v6a.75.75 0 0 1-.22.53l-4.25 4.25A.75.75 0 0 1 11 16H5a.75.75 0 0 1-.53-.22L.22 11.53A.75.75 0 0 1 0 11V5c0-.2.079-.39.22-.53L4.47.22Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5H5.31ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 6a.75.75 0 1 1 0 1.5A.75.75 0 0 1 8 10Z"></path></svg>'
                    }
                    $titleText = $titleMap[$type]
                    $svgIcon = $svgMap[$type]
                    
                    $html.Add("<div class=`"callout callout-$($type.ToLower())`">")
                    $html.Add("    <div class=`"callout-title`">$svgIcon$titleText</div>")
                    $html.Add("    $innerHtml")
                    $html.Add("</div>")
                } elseif ($state.hasPendingCharacter) {
                    $innerMarkdown = $blockquoteLines -join "`n"
                    $innerHtml = Convert-MarkdownToHtml -MarkdownText $innerMarkdown
                    
                    $parentheticalHtml = ""
                    if ($state.pendingParenthetical) {
                        $parentheticalHtml = "<span class=`"script-parenthetical`">$(Convert-InlineMarkdown $state.pendingParenthetical)</span>"
                    }
                    
                    $html.Add("<div class=`"script-dialogue`">")
                    $html.Add("    <div class=`"script-character`">")
                    $html.Add("        <span class=`"name`">$($state.pendingCharacter)</span>")
                    $html.Add("        $parentheticalHtml")
                    $html.Add("    </div>")
                    $html.Add("    <div class=`"script-text`">")
                    $html.Add("        $innerHtml")
                    $html.Add("    </div>")
                    $html.Add("</div>")
                    
                    $state.hasPendingCharacter = $false
                } else {
                    $innerMarkdown = $blockquoteLines -join "`n"
                    $innerHtml = Convert-MarkdownToHtml -MarkdownText $innerMarkdown
                    $html.Add("<blockquote>`n$innerHtml`n</blockquote>")
                }
                $blockquoteLines.Clear()
            }
            $state.inBlockquote = $false
        }
    }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($line -match '^\s*```') {
            Close-Table
            Flush-Blockquote
            Flush-PendingCharacter
            Flush-Paragraph
            Close-Lists
            if ($state.inCode) {
                $html.Add("<pre><code>$(Escape-Html ($code -join "`n"))</code></pre>")
                $code.Clear()
                $state.inCode = $false
            } else {
                $state.inCode = $true
            }
            continue
        }

        if ($state.inCode) {
            $code.Add($line)
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            Close-Table
            Flush-Paragraph
            Close-Lists
            Flush-Blockquote
            continue
        }

        if ($line -match '^\s*\*\*【(.+)】\*\*\s*$') {
            Close-Table
            Flush-Blockquote
            Flush-PendingCharacter
            Flush-Paragraph
            Close-Lists
            $html.Add("<p class=`"stage-direction`">【$($Matches[1])】</p>")
            continue
        }

        if ($line -match '^\s*\*\*([^*]+)\*\*\s*([（(].+?[）)])?\s*[：:]\s*$') {
            Close-Table
            Flush-Blockquote
            Flush-PendingCharacter
            Flush-Paragraph
            Close-Lists
            $state.hasPendingCharacter = $true
            $state.pendingCharacter = $Matches[1].Trim()
            $state.pendingParenthetical = if ($Matches[2]) { $Matches[2].Trim() } else { "" }
            continue
        }

        if ($line -match '^\s*>\s?(.*)$') {
            Close-Table
            Flush-Paragraph
            Close-Lists
            if (-not $state.inBlockquote) {
                $state.inBlockquote = $true
                $blockquoteLines.Clear()
            }
            $blockquoteLines.Add($Matches[1])
            continue
        }

        # Check if table starts
        if (-not $state.inTable -and $line -match '\|' -and ($i + 1 -lt $Lines.Count) -and $Lines[$i + 1] -match '^\s*\|?(\s*[:-]+\s*\|)+\s*$') {
            Close-Lists
            Flush-Paragraph
            Flush-Blockquote
            Flush-PendingCharacter
            
            $state.inTable = $true
            
            # Parse header row
            $rawHeaderCells = $line.Split('|')
            $headerCells = New-Object System.Collections.Generic.List[string]
            for ($idx = 0; $idx -lt $rawHeaderCells.Length; $idx++) {
                if (($idx -eq 0 -or $idx -eq ($rawHeaderCells.Length - 1)) -and [string]::IsNullOrWhiteSpace($rawHeaderCells[$idx])) {
                    continue
                }
                $headerCells.Add($rawHeaderCells[$idx].Trim())
            }
            
            # Parse separator row (which is at index $i + 1)
            $i++
            $separatorLine = $Lines[$i]
            $rawSepCells = $separatorLine.Split('|')
            $sepCells = New-Object System.Collections.Generic.List[string]
            for ($idx = 0; $idx -lt $rawSepCells.Length; $idx++) {
                if (($idx -eq 0 -or $idx -eq ($rawSepCells.Length - 1)) -and [string]::IsNullOrWhiteSpace($rawSepCells[$idx])) {
                    continue
                }
                $sepCells.Add($rawSepCells[$idx].Trim())
            }
            
            # Determine alignments
            $tableAlignments.Clear()
            foreach ($cell in $sepCells) {
                $left = $cell.StartsWith(":")
                $right = $cell.EndsWith(":")
                if ($left -and $right) {
                    $tableAlignments.Add("center")
                } elseif ($right) {
                    $tableAlignments.Add("right")
                } elseif ($left) {
                    $tableAlignments.Add("left")
                } else {
                    $tableAlignments.Add("")
                }
            }
            
            # Output table header
            $headerHtml = New-Object System.Collections.Generic.List[string]
            for ($c = 0; $c -lt $headerCells.Count; $c++) {
                $align = if ($c -lt $tableAlignments.Count) { $tableAlignments[$c] } else { "" }
                $styleAttr = if ($align) { " style=`"text-align: $align;`"" } else { "" }
                $headerHtml.Add("<th$styleAttr>$(Convert-InlineMarkdown $headerCells[$c])</th>")
            }
            
            $html.Add("<table class=`"table table-striped table-bordered`">")
            $html.Add("<thead>")
            $html.Add("<tr>")
            foreach ($th in $headerHtml) {
                $html.Add("  $th")
            }
            $html.Add("</tr>")
            $html.Add("</thead>")
            $html.Add("<tbody>")
            continue
        }

        if ($state.inTable) {
            if ($line -match '\|') {
                # Parse body row
                $rawCells = $line.Split('|')
                $bodyCells = New-Object System.Collections.Generic.List[string]
                for ($idx = 0; $idx -lt $rawCells.Length; $idx++) {
                    if (($idx -eq 0 -or $idx -eq ($rawCells.Length - 1)) -and [string]::IsNullOrWhiteSpace($rawCells[$idx])) {
                        continue
                    }
                    $bodyCells.Add($rawCells[$idx].Trim())
                }
                
                $rowHtml = New-Object System.Collections.Generic.List[string]
                for ($c = 0; $c -lt $bodyCells.Count; $c++) {
                    $align = if ($c -lt $tableAlignments.Count) { $tableAlignments[$c] } else { "" }
                    $styleAttr = if ($align) { " style=`"text-align: $align;`"" } else { "" }
                    $rowHtml.Add("<td$styleAttr>$(Convert-InlineMarkdown $bodyCells[$c])</td>")
                }
                $html.Add("<tr>")
                foreach ($td in $rowHtml) {
                    $html.Add("  $td")
                }
                $html.Add("</tr>")
                continue
            } else {
                Close-Table
            }
        }

        Flush-Blockquote
        Flush-PendingCharacter

        if ($line -match '^(#{1,6})\s+(.+)$') {
            Flush-Paragraph
            Close-Lists
            $level = $Matches[1].Length
            $rawText = $Matches[2].Trim()
            $text = Convert-InlineMarkdown $rawText
            
            # Generate id for headers to support anchor links
            $id = $rawText.ToLowerInvariant()
            $id = $id -replace '[^\w\s\-\p{IsCJKUnifiedIdeographs}]', ''
            $id = $id -replace '[\s_]+', '-'
            $id = $id.Trim('-')
            
            $html.Add("<h$level id=`"$id`">$text</h$level>")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.+)$') {
            Flush-Paragraph
            if ($state.inOl) {
                $html.Add("</ol>")
                $state.inOl = $false
            }
            if (-not $state.inUl) {
                $html.Add("<ul>")
                $state.inUl = $true
            }
            $html.Add("<li>$(Convert-InlineMarkdown $Matches[1].Trim())</li>")
            continue
        }

        if ($line -match '^\s*\d+\.\s+(.+)$') {
            Flush-Paragraph
            if ($state.inUl) {
                $html.Add("</ul>")
                $state.inUl = $false
            }
            if (-not $state.inOl) {
                $html.Add("<ol>")
                $state.inOl = $true
            }
            $html.Add("<li>$(Convert-InlineMarkdown $Matches[1].Trim())</li>")
            continue
        }

        $paragraph.Add($line.Trim())
    }

    Flush-Paragraph
    Close-Lists
    Close-Table
    Flush-Blockquote
    Flush-PendingCharacter

    if ($state.inCode) {
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

		/* Code and text diagrams styling */
		.daily-article pre code {
			font-family: var(--bs-font-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace);
			font-size: 0.95em;
		}
		.daily-article code {
			font-family: var(--bs-font-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace);
			background-color: rgba(175, 184, 193, 0.2);
			padding: 0.2em 0.4em;
			border-radius: 6px;
			font-size: 85%;
		}
		.daily-article pre code {
			background-color: transparent;
			padding: 0;
			border-radius: 0;
			font-size: inherit;
		}

		/* Stage directions in theatrical play script */
		.daily-article .stage-direction {
			font-style: italic;
			color: #55595c;
			background-color: #f1f3f5;
			border-left: 4px solid #adb5bd;
			padding: 0.5rem 1rem;
			margin: 1.25rem 0;
			border-radius: 0 0.375rem 0.375rem 0;
			font-size: 0.95rem;
		}

		/* Theatrical script dialogue formatting */
		.daily-article .script-dialogue {
			margin: 1.25rem 0;
			padding: 1rem 1.25rem;
			border: 1px solid #e9ecef;
			border-radius: 0.5rem;
			background-color: #fafbfc;
			box-shadow: 0 1px 3px rgba(0,0,0,0.02);
		}
		.daily-article .script-character {
			font-weight: 700;
			color: #333333;
			margin-bottom: 0.5rem;
			font-size: 1rem;
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 0.35rem;
		}
		.daily-article .script-character .name {
			background-color: #212529;
			color: #ffffff;
			padding: 0.15rem 0.5rem;
			border-radius: 0.25rem;
			font-size: 0.85rem;
			letter-spacing: 0.05em;
		}
		.daily-article .script-character .parenthetical {
			font-weight: 400;
			font-style: italic;
			color: #6c757d;
			font-size: 0.9rem;
		}
		.daily-article .script-text {
			font-size: 1.05rem;
			line-height: 1.7;
			color: #212529;
			padding-left: 0.5rem;
		}
		.daily-article .script-text p:last-child {
			margin-bottom: 0;
		}

		/* GitHub-style Markdown callout alerts */
		.daily-article .callout {
			margin: 1.5rem 0;
			padding: 1rem 1.25rem;
			border-left: 4px solid;
			border-radius: 0 0.375rem 0.375rem 0;
		}
		.daily-article .callout-title {
			font-weight: 700;
			margin-bottom: 0.5rem;
			display: flex;
			align-items: center;
			gap: 0.25rem;
			font-size: 0.95rem;
			text-transform: uppercase;
		}
		.daily-article .callout p:last-child {
			margin-bottom: 0;
		}
		.daily-article .callout-note {
			background-color: #f0f7ff;
			border-color: #0969da;
			color: #1f2328;
		}
		.daily-article .callout-note .callout-title {
			color: #0969da;
		}
		.daily-article .callout-tip {
			background-color: #f2fcf5;
			border-color: #1a7f37;
			color: #1f2328;
		}
		.daily-article .callout-tip .callout-title {
			color: #1a7f37;
		}
		.daily-article .callout-important {
			background-color: #fbf5ff;
			border-color: #8250df;
			color: #1f2328;
		}
		.daily-article .callout-important .callout-title {
			color: #8250df;
		}
		.daily-article .callout-warning {
			background-color: #fffdf5;
			border-color: #9a6700;
			color: #1f2328;
		}
		.daily-article .callout-warning .callout-title {
			color: #9a6700;
		}
		.daily-article .callout-caution {
			background-color: #ffebe9;
			border-color: #cf222e;
			color: #1f2328;
		}
		.daily-article .callout-caution .callout-title {
			color: #cf222e;
		}

		/* Table styling */
		.daily-article table {
			width: 100%;
			margin: 1.5rem 0;
			border-collapse: collapse;
			font-size: 0.95rem;
		}
		.daily-article th, .daily-article td {
			padding: 0.6rem 0.8rem;
			border: 1px solid #dee2e6;
		}
		.daily-article th {
			background-color: #f8f9fa;
			font-weight: 600;
		}
		.daily-article tbody tr:nth-of-type(even) {
			background-color: rgba(0, 0, 0, 0.02);
		}

		/* Footnote styling */
		.daily-article .footnote {
			font-size: 0.9rem;
			color: #6c757d;
			margin-top: 2rem;
			padding-top: 0.75rem;
			border-top: 1px dashed #dee2e6;
		}
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
				<form id="search" method="GET" action="https://www.bing.com/search" onsubmit="this.q.value = this.querySelector('#google-search').value + ' site:zerotracephoto.com/blog';">
					<label for="google-search">Search:</label>
					<input id="google-search" type="text" maxlength="255" value="" placeholder="搜索本站内容" required>
					<input type="hidden" name="q">
					<input type="submit" value="Bing">
					(By <a href="https://www.bing.com/">Bing</a>)
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


