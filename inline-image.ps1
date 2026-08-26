# Strips metadata from aloituskuva.JPG and re-inlines it into index.html.
#
#   .\inline-image.ps1               # clean + inline
#   .\inline-image.ps1 -InspectOnly  # just report what metadata is in there
#
# Screenshots carry EXIF/XMP nobody asked for — this one had dc:creator with a
# full name in it, which then travelled inside the game as base64 where no one
# would ever think to look. Rather than hand-parsing JPEG marker segments (a
# first attempt at that produced a 0-byte file), the image is redrawn onto a
# brand-new Bitmap, which has no property items by construction, and re-encoded
# at high quality. A screenshot of flat UI loses nothing visible at q=94.

param(
  [string]$Image = (Join-Path $PSScriptRoot "aloituskuva.JPG"),
  [string]$Html  = (Join-Path $PSScriptRoot "index.html"),
  [int]$Quality  = 94,
  [switch]$InspectOnly
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $Image)) { throw "image not found: $Image" }
$src = [IO.File]::ReadAllBytes($Image)
$latin = [Text.Encoding]::GetEncoding(28591)

function Show-Meta([byte[]]$b, [string]$label) {
  $txt = $latin.GetString($b, 0, [Math]::Min(20000, $b.Length))
  $found = @()
  foreach ($t in @("Exif","xmpmeta","dc:creator","photoshop","Adobe","GPS")) {
    if ($txt.Contains($t)) { $found += $t }
  }
  $names = [regex]::Matches($txt, '[\x20-\x7E]{4,}') | ForEach-Object { $_.Value } |
           Where-Object { $_ -match '(?i)creator|author|rvel|aakko' } | Select-Object -First 3
  $mk = if ($found.Count) { $found -join ", " } else { "none" }
  Write-Host ("  " + $label.PadRight(8) + " markers: " + $mk)
  foreach ($n in $names) { Write-Host ("           name: " + $n.Substring(0,[Math]::Min(60,$n.Length))) }
  # XP tags keep names as UTF-16, which the ASCII scan above would miss
  $u16 = [Text.Encoding]::Unicode.GetString($b, 0, [Math]::Min(20000, $b.Length))
  if ($u16 -match '(?i)aakko|rvel') { Write-Host "           name: (also present as UTF-16)" }
}

Write-Host ("image     : " + (Split-Path $Image -Leaf) + "  " + [math]::Round($src.Length/1KB,1) + " KB")
Show-Meta $src "before"

if ($InspectOnly) { Write-Host "inspect only - nothing written."; exit 0 }

# --- redraw onto a fresh surface, then encode ------------------------------
$inStream = New-Object IO.MemoryStream($src, 0, $src.Length)
$img  = [System.Drawing.Image]::FromStream($inStream)
$bmp  = New-Object System.Drawing.Bitmap($img.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gfx  = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gfx.DrawImage($img, 0, 0, $img.Width, $img.Height)

$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
         Where-Object { $_.MimeType -eq "image/jpeg" }
$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                 [System.Drawing.Imaging.Encoder]::Quality, [int]$Quality)

$outStream = New-Object IO.MemoryStream
$bmp.Save($outStream, $codec, $ep)
$clean = $outStream.ToArray()

$dims = "" + $img.Width + "x" + $img.Height
$gfx.Dispose(); $bmp.Dispose(); $img.Dispose(); $inStream.Dispose(); $outStream.Dispose()

if ($clean.Length -lt 5000) { throw "output implausibly small ($($clean.Length) bytes) - refusing to write" }

Show-Meta $clean "after"
Write-Host ("  size     : " + [math]::Round($src.Length/1KB,1) + " KB -> " +
            [math]::Round($clean.Length/1KB,1) + " KB   (" + $dims + ", q$Quality)")

# it must still decode before we trust it
$chk = New-Object IO.MemoryStream($clean, 0, $clean.Length)
try {
  $t = [System.Drawing.Image]::FromStream($chk)
  Write-Host ("  decodes  : yes, " + $t.Width + "x" + $t.Height)
  $t.Dispose()
} catch { throw "stripped image no longer decodes - refusing to write" } finally { $chk.Dispose() }

[IO.File]::WriteAllBytes($Image, $clean)

# --- re-inline into index.html ---------------------------------------------
if (-not (Test-Path $Html)) { throw "index.html not found: $Html" }
$page = [IO.File]::ReadAllText($Html)
$m = [regex]::Match($page, '--aloitus:\s*url\("data:image/jpeg;base64,[^"]*"\);')
if (-not $m.Success) { throw "could not find the --aloitus data URI in index.html" }
$page = $page.Replace($m.Value,
        '--aloitus: url("data:image/jpeg;base64,' + [Convert]::ToBase64String($clean) + '");')
[IO.File]::WriteAllText($Html, $page, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("index.html: " + [math]::Round((Get-Item $Html).Length/1MB,2) + " MB") -ForegroundColor Green
Write-Host "done."
