# Fails if the guide links to any GitHub repo that isn't public.
#
# This repo is public, so every github.com / raw.githubusercontent.com link must resolve to a public
# repo. The check asks GitHub's API WITHOUT credentials: a public repo answers 200 with
# "private": false; a private or missing repo answers 404 and fails the check.
#
#   pwsh -File tools/check-public-refs.ps1
#
# Exit code 0 = every linked repo is public; 1 = at least one isn't (listed with where it's cited).
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$pattern = '(?:https?://)?(?:github\.com|raw\.githubusercontent\.com)/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)'
$files = Get-ChildItem -Path $Root -Recurse -File -Include *.md, *.txt, *.ps1, *.json |
  Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules)[\\/]' }

$cites = @{}
foreach ($f in $files) {
  $n = 0
  foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
    $n++
    foreach ($m in [regex]::Matches($line, $pattern)) {
      $repo = ("{0}/{1}" -f $m.Groups[1].Value, ($m.Groups[2].Value -replace '\.git$', ''))
      if (-not $cites.ContainsKey($repo)) { $cites[$repo] = New-Object System.Collections.ArrayList }
      [void]$cites[$repo].Add(("{0}:{1}" -f $f.FullName.Substring($Root.Length).TrimStart('\', '/'), $n))
    }
  }
}

$bad = 0
foreach ($repo in ($cites.Keys | Sort-Object)) {
  $status = "public"
  try {
    $res = Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "1health-app-guide-check"; "Accept" = "application/vnd.github+json" } -Uri "https://api.github.com/repos/$repo"
    if (($res.Content | ConvertFrom-Json).private) { $status = "PRIVATE" }
  } catch {
    $code = $null
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $status = if ($code -eq 404) { "PRIVATE or missing" } else { "UNCHECKED ($($_.Exception.Message))" }
  }
  if ($status -eq "public") {
    "ok        $repo  ($($cites[$repo].Count) refs)"
  } else {
    $bad++
    "FAIL      $repo  -> $status"
    $cites[$repo] | Select-Object -First 10 | ForEach-Object { "            $_" }
  }
}
"repos linked: $($cites.Count); not public: $bad"
if ($bad -gt 0) { exit 1 }
