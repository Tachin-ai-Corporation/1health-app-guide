# Every agents.1health.io link in the guide must land on a page that DOCUMENTS a route
# (has at least one "## METHOD /path" heading) - not a 404, and not a child-route index.
# Usage (from the repo root):  pwsh -File tools/check-doc-links.ps1
# Note: URLs inside code spans (illustrative patterns) are reported too; ignore those.
param([string]$Guide = (Split-Path $PSScriptRoot -Parent))
$nonRoutePages = @(
  'https://agents.1health.io/public/prod/api/manifest.md',
  'https://agents.1health.io/public/prod/llms.txt',
  'https://agents.1health.io/public/prod/api/agents.md',
  'https://agents.1health.io/public/prod/api/authentication/agents.md'
)
$links = @{}
Get-ChildItem $Guide -Recurse -File -Include *.md, *.txt | Where-Object { $_.FullName -notmatch '\\\.git\\' } | ForEach-Object {
  $rel = $_.FullName.Substring($Guide.Length + 1)
  $n = 0
  foreach ($line in (Get-Content $_.FullName -Encoding UTF8)) {
    $n++
    foreach ($m in [regex]::Matches($line, 'https://agents\.1health\.io/[^\s\)\]>"''`]+')) {
      $u = $m.Value.TrimEnd('.', ',', ';', ':')
      if (-not $links.ContainsKey($u)) { $links[$u] = New-Object System.Collections.Generic.List[string] }
      $links[$u].Add("$rel`:$n")
    }
  }
}
"distinct agents.1health.io links: $($links.Count)"
$bad = 0
foreach ($u in ($links.Keys | Sort-Object)) {
  if ($nonRoutePages -contains $u) { continue }
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    $isRoutePage = $r.Content -match '(?m)^## (GET|POST|PUT|PATCH|DELETE) /'
    $isExamples = $u -match '/examples\.md$'
    if (-not $isRoutePage -and -not $isExamples) { $bad++; "CHILD-INDEX  $u  <- $(($links[$u] | Select-Object -First 3) -join ', ')" }
  } catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { -1 }
    $bad++; "BROKEN($code)  $u  <- $(($links[$u] | Select-Object -First 3) -join ', ')"
  }
}
if ($bad) { "ISSUES: $bad link(s)" } else { "ALL LINKS LAND ON DOCUMENTING PAGES" }
