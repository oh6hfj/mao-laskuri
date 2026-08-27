# Inlines a background-music file into index.html as a data: URI, so the game
# stays a single self-contained file that works offline and as an Artifact.
#
#   .\inline-music.ps1                     # auto-detect an audio file here
#   .\inline-music.ps1 -Audio path\to.mp3  # use a specific file
#   .\inline-music.ps1 -Clear              # remove the track again
#
# Re-runnable: it replaces whatever MUSIC_SRC currently holds.

param(
  [string]$Audio,
  [string]$Ping,
  [string]$Panda,
  [string]$Html = (Join-Path $PSScriptRoot "index.html"),
  [switch]$Clear
)
$ErrorActionPreference = "Stop"

function Get-DataUri([string]$path) {
  $f = Get-Item $path
  $mime = switch ($f.Extension.ToLower()) {
    ".mp3"  { "audio/mpeg" }
    ".m4a"  { "audio/mp4" }
    ".aac"  { "audio/aac" }
    ".ogg"  { "audio/ogg" }
    ".opus" { "audio/ogg" }
    ".wav"  { "audio/wav" }
    ".flac" { "audio/flac" }
    default { throw ("unsupported audio type: " + $f.Extension) }
  }
  return "data:$mime;base64," + [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
}

# An Artifact must render under 16 MB and base64 adds ~33%, on top of ~200 KB
# of page. Warn well before the wall so the failure is not a mystery later.
$SoftLimitMB = 4
$HardLimitMB = 11

# NOTE: PowerShell variable names are case-insensitive, so $html and $Html are
# the SAME variable. The page text must not be named anything like $Html or it
# clobbers the path.
if (-not (Test-Path $Html)) { throw "index.html not found at $Html" }
$page = [IO.File]::ReadAllText($Html)
$m = [regex]::Match($page, 'var MUSIC_SRC = "[^"]*";')
if (-not $m.Success) { throw "could not find the MUSIC_SRC line in index.html" }

$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($Clear) {
  $page = $page.Replace($m.Value, 'var MUSIC_SRC = "";')
  $pmc = [regex]::Match($page, 'var PING_SRC = "[^"]*";')
  if ($pmc.Success) { $page = $page.Replace($pmc.Value, 'var PING_SRC = "";') }
  [IO.File]::WriteAllText($Html, $page, $utf8)
  Write-Host "MUSIC_SRC cleared - the game will run without music."
  exit 0
}

# --- the bat-hit sample (ping.*) is handled first and kept out of the music
#     candidates; it is newer than the music file, so auto-detect would
#     otherwise happily inline the sound effect as the soundtrack.
if (-not $Ping) {
  $pingFile = Get-ChildItem -Path $PSScriptRoot -File -ErrorAction SilentlyContinue |
              Where-Object { $_.BaseName -ieq "ping" }
  if ($pingFile) { $Ping = $pingFile[0].FullName }
}
if ($Ping -and (Test-Path $Ping)) {
  $pm = [regex]::Match($page, 'var PING_SRC = "[^"]*";')
  if (-not $pm.Success) { throw "could not find the PING_SRC line in index.html" }
  $pf = Get-Item $Ping
  $page = $page.Replace($pm.Value, ('var PING_SRC = "' + (Get-DataUri $pf.FullName) + '";'))
  Write-Host ("bat sample : " + $pf.Name + "  (" + [math]::Round($pf.Length/1KB,1) + " KB)")
}

# --- the panda sound (panda.*), same treatment
if (-not $Panda) {
  $pandaFile = Get-ChildItem -Path $PSScriptRoot -File -ErrorAction SilentlyContinue |
               Where-Object { $_.BaseName -ieq "panda" }
  if ($pandaFile) { $Panda = $pandaFile[0].FullName }
}
if ($Panda -and (Test-Path $Panda)) {
  $am = [regex]::Match($page, 'var PANDA_SRC = "[^"]*";')
  if (-not $am.Success) { throw "could not find the PANDA_SRC line in index.html" }
  $af = Get-Item $Panda
  $page = $page.Replace($am.Value, ('var PANDA_SRC = "' + (Get-DataUri $af.FullName) + '";'))
  Write-Host ("panda sound: " + $af.Name + "  (" + [math]::Round($af.Length/1KB,1) + " KB)")
} else {
  Write-Host "panda sound: none yet - the game uses a synthesised fallback"
}
# --- optional one-shots. Drop gong.mp3 / whiff.mp3 / escape.mp3 in this folder
#     and they replace the synthesised versions; leave one out and that sound
#     stays synthesised. Same onset-trimming applies as to the bat sample.
foreach ($one in @(
    @{ base = "gong";   var = "GONG_SRC";   label = "gong (over)" },
    @{ base = "whiff";  var = "WHIFF_SRC";  label = "whiff      " },
    @{ base = "escape"; var = "ESCAPE_SRC"; label = "escaped    " })) {
  $om2 = [regex]::Match($page, ('var ' + $one.var + ' = "[^"]*";'))
  if (-not $om2.Success) { throw ("could not find " + $one.var + " in index.html") }
  $hit = Get-ChildItem -Path $PSScriptRoot -File -ErrorAction SilentlyContinue |
         Where-Object { $_.BaseName -ieq $one.base -and
                        $_.Extension -match '(?i)\.(mp3|m4a|ogg|opus|wav|aac|flac)$' }
  if ($hit) {
    $hf = $hit[0]
    $page = $page.Replace($om2.Value, ('var ' + $one.var + ' = "' + (Get-DataUri $hf.FullName) + '";'))
    Write-Host ($one.label + ": " + $hf.Name + "  (" + [math]::Round($hf.Length/1KB,1) + " KB)")
  } else {
    Write-Host ($one.label + ": none - synthesised")
  }
}

if (-not $Audio) {
  $exts = @("*.mp3","*.m4a","*.ogg","*.opus","*.wav","*.aac","*.flac")
  $found = @()
  foreach ($e in $exts) {
    $found += Get-ChildItem -Path $PSScriptRoot -Filter $e -File -ErrorAction SilentlyContinue
  }
  $found = $found | Where-Object { $_.BaseName -notin @("gong","whiff","escape") -and $_.BaseName -ine "ping" -and $_.BaseName -ine "panda" }
  if ($found.Count -eq 0) {
    # nothing but the ping - keep whatever music is already inlined
    [IO.File]::WriteAllText($Html, $page, $utf8)
    Write-Host ("index.html : " + [math]::Round((Get-Item $Html).Length/1MB,2) + " MB") -ForegroundColor Green
    Write-Host "done - music left as it was."
    exit 0
  }
  if ($found.Count -gt 1) {
    Write-Host "several audio files found:"
    $found | ForEach-Object { Write-Host ("  " + $_.Name) }
    $Audio = ($found | Sort-Object LastWriteTime -Descending)[0].FullName
    Write-Host ("using the newest: " + (Split-Path $Audio -Leaf))
  } else {
    $Audio = $found[0].FullName
  }
}
if (-not (Test-Path $Audio)) { throw "audio file not found: $Audio" }

$file = Get-Item $Audio
$mb = [math]::Round($file.Length / 1MB, 2)
$mime = switch ($file.Extension.ToLower()) {
  ".mp3"  { "audio/mpeg" }
  ".m4a"  { "audio/mp4" }
  ".aac"  { "audio/aac" }
  ".ogg"  { "audio/ogg" }
  ".opus" { "audio/ogg" }
  ".wav"  { "audio/wav" }
  ".flac" { "audio/flac" }
  default { throw ("unsupported audio type: " + $file.Extension) }
}

$b64MB = [math]::Round(($file.Length * 4 / 3) / 1MB, 2)
Write-Host ("track      : " + $file.Name)
Write-Host ("size       : $mb MB  ->  ~$b64MB MB inlined")
if ($mb -gt $HardLimitMB) {
  throw "too large: $mb MB would exceed the 16 MB Artifact ceiling once inlined. Re-encode lower (128 kbps mono is plenty)."
}
if ($mb -gt $SoftLimitMB) {
  Write-Host "NOTE: over $SoftLimitMB MB - it will work, but the page will be slow to load on mobile." -ForegroundColor Yellow
}

$uri = "data:$mime;base64," + [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
# plain String.Replace, not regex - a replacement that large should never be
# scanned for $1-style backreferences
$page = $page.Replace($m.Value, ('var MUSIC_SRC = "' + $uri + '";'))
[IO.File]::WriteAllText($Html, $page, $utf8)

$outMB = [math]::Round((Get-Item $Html).Length / 1MB, 2)
Write-Host ("index.html : $outMB MB") -ForegroundColor Green
Write-Host "done - reload the page to hear it."
