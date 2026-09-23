# Audit: every METHOD + path cited in the guide must be documented in 1health's public API docs -
# either listed in the manifest or as a "## METHOD /path" heading on its collection's page.
# Usage (from the repo root):  pwsh -File tools/audit-routes.ps1 [-Out report.md]
# Anything reported as missing must be a route 1health supports but hasn't documented yet, and the
# recipe that teaches it must carry the "Not yet in 1health's published API docs" banner.
param(
  [string]$Guide = (Split-Path $PSScriptRoot -Parent),
  [string]$Manifest = "",
  [string]$Out = "",
  [string]$ExcludePattern = '[\\/]\.git[\\/]|[\\/]tools[\\/]'
)
if (-not $Manifest) {
  $Manifest = Join-Path ([IO.Path]::GetTempPath()) "1health-manifest.md"
  Invoke-WebRequest -Uri "https://agents.1health.io/public/prod/api/manifest.md" -OutFile $Manifest -UseBasicParsing
}

$verbs = 'GET|POST|PUT|PATCH|DELETE'

function Normalize-Path([string]$p) {
  $p = $p.Trim()
  $p = $p -replace '\?.*$', ''                 # drop query string
  $p = $p -replace '[\.\:\)\]''"`,;]+$', ''    # drop trailing punctuation
  $p = $p -replace '^/api(?=/)', ''            # guide writes /api/v2/..., manifest writes /v2/...
  $p = $p -replace '\$\{[^}]*\}', '{}'         # template literals
  $p = $p -replace '\{[^}]*\}', '{}'           # {param} -> {}
  $p = $p -replace '/_[A-Za-z0-9]+_(?=/|$)', '/{}'   # docs-URL param fold: /_fileId_ -> /{}
  $p = $p.TrimEnd('/')
  return $p
}

# "/v3/patient[/{id}]" -> @("/v3/patient", "/v3/patient/{}")  (optional trailing segment)
function Expand-Variants([string]$raw) {
  $raw = $raw.TrimEnd(']')
  $i = $raw.IndexOf('[')
  if ($i -lt 0) { return @(Normalize-Path $raw) }
  $base = $raw.Substring(0, $i)
  $opt = $raw.Substring($i + 1).Replace(']', '')
  return @((Normalize-Path $base), (Normalize-Path ($base + $opt)))
}

# ---- manifest: "- [GET, POST /v2/boi/all] (url) -- summary"
$manifestSet = @{}
$manifestPaths = @{}
foreach ($line in Get-Content $Manifest -Encoding UTF8) {
  $m = [regex]::Match($line, '^\- \[(?<methods>[A-Z, ]+?) (?<path>/[^\]]+)\]')
  if (-not $m.Success) { continue }
  $path = Normalize-Path $m.Groups['path'].Value
  $manifestPaths[$path] = $true
  foreach ($verb in ($m.Groups['methods'].Value -split '[,\s]+' | Where-Object { $_ })) {
    $manifestSet["$verb $path"] = $true
  }
}

# ---- guide citations: "GET /api/v2/x", "GET/POST/PATCH /api/v2/x", "GET, POST /v2/x"
$citeRx = "(?<methods>\b(?:$verbs)(?:\s*[,/|]\s*(?:$verbs))*)\s+``?(?<path>/(?:api/)?v[0-9]/[^\s``\)\|,;]+)"
$files = Get-ChildItem $Guide -Recurse -File -Include *.md, *.txt | Where-Object { $_.FullName -notmatch $ExcludePattern }

$missing = New-Object System.Collections.Generic.List[object]
$placeholder = New-Object System.Collections.Generic.List[object]
$okCount = 0
foreach ($f in $files) {
  $rel = $f.FullName.Substring($Guide.Length).TrimStart('\')
  $n = 0
  foreach ($line in Get-Content $f.FullName -Encoding UTF8) {
    $n++
    foreach ($c in [regex]::Matches($line, $citeRx)) {
      $raw = $c.Groups['path'].Value
      # a "](...)" markdown tail can't be part of a route; cut it
      $cut = $raw.IndexOf('](')
      if ($cut -ge 0) { $raw = $raw.Substring(0, $cut) }
      if ($raw -match '\.\.\.|\u2026|<|>|\*') { $placeholder.Add([pscustomobject]@{ File=$rel; Line=$n; Cite="$($c.Groups['methods'].Value) $raw" }); continue }
      $variants = Expand-Variants $raw
      $shown = $variants -join '  |  '
      foreach ($verb in ($c.Groups['methods'].Value -split '[,/|\s]+' | Where-Object { $_ })) {
        $hit = $false
        foreach ($v in $variants) { if ($manifestSet.ContainsKey("$verb $v")) { $hit = $true } }
        if ($hit) { $okCount++ }
        else {
          $pathKnown = $false
          foreach ($v in $variants) { if ($manifestPaths.ContainsKey($v)) { $pathKnown = $true } }
          $why = if ($pathKnown) { "path exists, METHOD not listed" } else { "path not in manifest" }
          $missing.Add([pscustomobject]@{ File=$rel; Line=$n; Route="$verb $shown"; Why=$why })
        }
      }
    }
  }
}

# ---- second pass: the manifest folds item routes (e.g. PUT /v1/boi/{id}) into their collection's
# page, so a manifest miss is only real if no agents.md page documents it as a "## VERB /path" heading.
# Check the page of the path truncated before its first {param}, plus the full literal path.
$docCache = @{}
function Get-DocHeadings([string]$docPath) {
  if ($docCache.ContainsKey($docPath)) { return $docCache[$docPath] }
  $u = "https://agents.1health.io/public/prod/api$docPath/agents.md"
  $heads = @()
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -ErrorAction Stop
    foreach ($l in ($r.Content -split "`n")) {
      $m = [regex]::Match($l, '^##\s+(?<v>GET|POST|PUT|PATCH|DELETE)\s+(?<p>/\S+)')
      if ($m.Success) { $heads += ("{0} {1}" -f $m.Groups['v'].Value, (Normalize-Path $m.Groups['p'].Value)) }
    }
  } catch { }
  $docCache[$docPath] = @{ Url = $u; Heads = $heads }
  return $docCache[$docPath]
}
$documentedOnParent = New-Object System.Collections.Generic.List[object]
$trulyMissing = New-Object System.Collections.Generic.List[object]
foreach ($x in $missing) {
  $verb = ($x.Route -split ' ', 2)[0]
  $variants = (($x.Route -split ' ', 2)[1] -split '\s+\|\s+')
  $found = $null
  foreach ($v in $variants) {
    $i = $v.IndexOf('/{}')
    $candidates = @($v)
    if ($i -gt 0) { $candidates += $v.Substring(0, $i) }
    foreach ($d in $candidates) {
      $page = Get-DocHeadings $d
      if ($page.Heads -contains "$verb $v") { $found = $page.Url; break }
    }
    if ($found) { break }
  }
  if ($found) { $documentedOnParent.Add([pscustomobject]@{ File=$x.File; Line=$x.Line; Route=$x.Route; DocUrl=$found }) }
  else { $trulyMissing.Add($x) }
}
$missing = $trulyMissing

$report = New-Object System.Text.StringBuilder
[void]$report.AppendLine("# Route audit vs public manifest")
[void]$report.AppendLine("")
[void]$report.AppendLine("- manifest routes (method+path): $($manifestSet.Count)")
[void]$report.AppendLine("- guide citations OK: $okCount")
[void]$report.AppendLine("- guide citations MISSING from manifest: $($missing.Count)  (unique routes: $(($missing | Select-Object -ExpandProperty Route -Unique).Count))")
[void]$report.AppendLine("- placeholder/elided citations (not checked): $($placeholder.Count)")
[void]$report.AppendLine("- documented only on a parent page (manifest folds them; link there): $($documentedOnParent.Count)")
[void]$report.AppendLine("")
[void]$report.AppendLine("## Documented on a parent page (not in manifest index, but real docs exist)")
foreach ($x in $documentedOnParent) { [void]$report.AppendLine("- $($x.Route) -- $($x.File):$($x.Line) -- docs: $($x.DocUrl)") }
[void]$report.AppendLine("")
[void]$report.AppendLine("## Missing -- grouped by route")
foreach ($g in ($missing | Group-Object Route | Sort-Object Name)) {
  $why = ($g.Group | Select-Object -First 1).Why
  [void]$report.AppendLine("- **$($g.Name)** -- $why")
  foreach ($x in $g.Group) { [void]$report.AppendLine("  - $($x.File):$($x.Line)") }
}
[void]$report.AppendLine("")
[void]$report.AppendLine("## Placeholder / elided citations (review by eye)")
foreach ($x in $placeholder) { [void]$report.AppendLine("- $($x.File):$($x.Line) -- $($x.Cite)") }

if ($Out) { $report.ToString() | Out-File -FilePath $Out -Encoding utf8; "report written: $Out" }
$report.ToString()
