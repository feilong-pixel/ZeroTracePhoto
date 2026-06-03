param(
  [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host "Serving static site at http://localhost:$Port/"
Write-Host "Press Ctrl+C to stop."

python -m http.server $Port
