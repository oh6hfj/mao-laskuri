# Inlines the webfonts into index.html so the page has NO external dependency
# at all — it then works opened straight from disk, offline, on any machine.
#
#   .\inline-fonts.ps1
#
# Google serves CJK families as ~100 unicode-range subsets. Pulling all of them
# would add megabytes, so this keeps only the subsets that actually cover the
# characters the game renders (Latin, a few accents, and the two seal glyphs
# 終 and 耻). Re-runnable: it replaces an existing inlined block.

param(
  [string]$Html = (Join-Path $PSScriptRoot "index.html")
)
$ErrorActionPreference = "Stop"
$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

if (-not (Test-Path $Html)) { throw "not found: $Html" }
$page = [IO.File]::ReadAllText($Html)
$utf8 = New-Object System.Text.UTF8Encoding($false)

# --- what the game actually needs -------------------------------------------
$needed = New-Object System.Collections.Generic.HashSet[int]
0x20..0x7E   | ForEach-Object { [void]$needed.Add($_) }   # ASCII
0xA0..0xFF   | ForEach-Object { [void]$needed.Add($_) }   # Latin-1 (ä ö ü)
0x100..0x17F | ForEach-Object { [void]$needed.Add($_) }   # Latin Ext-A (ş)
@(0x2013,0x2014,0x2018,0x2019,0x201C,0x201D,0x2022,0x2026,0x00B7,
  0x00D7,0x2212,0x2192,0x266A,0x266B,0x00B0,0x2032) | ForEach-Object { [void]$needed.Add($_) }
[void]$needed.Add(0x7D42)   # 終  Game Over seal
[void]$needed.Add(0x803B)   # 耻  Wall of Shame seal

# --- find the stylesheet link we are replacing -------------------------------
$linkRe = '<link rel="stylesheet" href="(https://fonts\.googleapis\.com/css2\?[^"]+)">'
$lm = [regex]::Match($page, $linkRe)
if (-not $lm.Success) {
  if ($page -match '/\* inlined webfonts \*/') { throw "fonts already inlined - nothing to do" }
  throw "could not find the Google Fonts <link> in index.html"
}
$cssUrl = $lm.Groups[1].Value -replace '&amp;','&'
Write-Host "fetching: $cssUrl"
$css = (Invoke-WebRequest -Uri $cssUrl -UserAgent $UA -UseBasicParsing -TimeoutSec 30).Content

# --- pick the subsets that intersect what we need ---------------------------
$blocks = [regex]::Matches($css, '(?s)@font-face\s*\{.*?\}')
Write-Host ("subsets offered : " + $blocks.Count)

function Test-RangeNeeded([string]$rangeDecl) {
  if ([string]::IsNullOrWhiteSpace($rangeDecl)) { return $true }   # no range = keep
  foreach ($tok in ($rangeDecl -split ',')) {
    $t = $tok.Trim() -replace '^[Uu]\+',''
    if ($t -match '^([0-9A-Fa-f]+)-([0-9A-Fa-f]+)$') {
      $a = [Convert]::ToInt32($Matches[1],16); $b = [Convert]::ToInt32($Matches[2],16)
      for ($cp = $a; $cp -le $b; $cp++) { if ($needed.Contains($cp)) { return $true } }
    } elseif ($t -match '^([0-9A-Fa-f]+)$') {
      if ($needed.Contains([Convert]::ToInt32($t,16))) { return $true }
    } elseif ($t -match '^([0-9A-Fa-f]+)\?+$') {
      $stem = $Matches[1]; $q = $t.Length - $stem.Length
      $a = [Convert]::ToInt32($stem + ("0" * $q),16)
      $b = [Convert]::ToInt32($stem + ("F" * $q),16)
      for ($cp = $a; $cp -le $b; $cp++) { if ($needed.Contains($cp)) { return $true } }
    }
  }
  return $false
}

$kept = @(); $total = 0
foreach ($b in $blocks) {
  $txt = $b.Value
  $u = [regex]::Match($txt, 'url\((https://[^)]+\.woff2)\)')
  if (-not $u.Success) { continue }
  $rng = [regex]::Match($txt, 'unicode-range:\s*([^;}]+)')
  if (-not (Test-RangeNeeded $rng.Groups[1].Value)) { continue }

  $bytes = (Invoke-WebRequest -Uri $u.Groups[1].Value -UserAgent $UA -UseBasicParsing -TimeoutSec 30).Content
  $total += $bytes.Length
  $dataUri = "data:font/woff2;base64," + [Convert]::ToBase64String($bytes)
  $kept += ($txt.Replace($u.Groups[1].Value, $dataUri))

  $fam = [regex]::Match($txt, "font-family:\s*'([^']+)'").Groups[1].Value
  Write-Host ("  + " + $fam.PadRight(16) + " " + [math]::Round($bytes.Length/1KB,1).ToString().PadLeft(6) + " KB")
}
if ($kept.Count -eq 0) { throw "no subsets selected - refusing to strip the fonts" }

Write-Host ("subsets inlined : " + $kept.Count + "  (" + [math]::Round($total/1KB,1) + " KB)")

$style = "<style>/* inlined webfonts - no external requests */`r`n" +
         ($kept -join "`r`n") + "`r`n</style>"
$page = $page.Replace($lm.Value, $style)

# the preconnect hints are pointless once nothing is fetched
$page = [regex]::Replace($page, '\s*<link rel="preconnect"[^>]*>', '')

[IO.File]::WriteAllText($Html, $page, $utf8)
Write-Host ("index.html      : " + [math]::Round((Get-Item $Html).Length/1MB,2) + " MB") -ForegroundColor Green
