param(
  [switch]$IncludeDrafts
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$args = @("tools/build-posts.js")
if ($IncludeDrafts) {
  $args += "--include-drafts"
}

node $args
