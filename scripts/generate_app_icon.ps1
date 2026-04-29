# Generates flutter\windows\runner\resources\app_icon.ico
#
# Draws the SAME flat brand mark used in-app (CipherNestMark) but in
# pure System.Drawing (.NET) so we don't depend on any image tool. The
# shape stays crisp at 16/24/32/48/64/128/256 px because every size is
# rendered from scratch — not downscaled from a photo.
#
# Re-run this any time the brand mark changes. Then do
#   flutter clean ; flutter build windows --debug
# so the resource compiler picks up the new ICO.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outIco   = Join-Path $repoRoot 'flutter\windows\runner\resources\app_icon.ico'

Add-Type -AssemblyName System.Drawing

# Brand accent — keep in sync with theme.dart primary
$accentHex = 'FF22D3EE'
$accent    = [System.Drawing.Color]::FromArgb(
    [Convert]::ToInt32($accentHex.Substring(0,2),16),
    [Convert]::ToInt32($accentHex.Substring(2,2),16),
    [Convert]::ToInt32($accentHex.Substring(4,2),16),
    [Convert]::ToInt32($accentHex.Substring(6,2),16))

function New-MarkBitmap {
    param([int] $sz)

    $bmp = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)

        $cx = $sz / 2.0
        $cy = $sz / 2.0
        $outerR = $sz * 0.46
        $stroke = [Math]::Max(1.2, $sz * 0.045)

        # 1. Inner tinted disc — gives the keyhole contrast at small sizes.
        $discColor = [System.Drawing.Color]::FromArgb(26, $accent.R, $accent.G, $accent.B)  # ~10% alpha
        $discBrush = New-Object System.Drawing.SolidBrush $discColor
        try {
            $dr = $outerR * 0.62
            $g.FillEllipse($discBrush, [single]($cx - $dr), [single]($cy - $dr), [single]($dr * 2), [single]($dr * 2))
        } finally { $discBrush.Dispose() }

        # 2. Three rotated thin ellipses — the woven nest.
        [single] $strokeF = $stroke
        $pen = [System.Drawing.Pen]::new($accent, $strokeF)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        try {
            $rectW = $outerR * 1.85
            $rectH = $outerR * 0.72
            for ($i = -1; $i -le 1; $i++) {
                $state = $g.Save()
                $g.TranslateTransform([single]$cx, [single]$cy)
                $g.RotateTransform([single]($i * 60))
                $g.DrawEllipse(
                    $pen,
                    [single](-$rectW / 2),
                    [single](-$rectH / 2),
                    [single]$rectW,
                    [single]$rectH)
                $g.Restore($state)
            }
        } finally { $pen.Dispose() }

        # 3. Solid keyhole — round head + tapered stem.
        $fill = New-Object System.Drawing.SolidBrush $accent
        try {
            $headR = $outerR * 0.18
            $headCy = $cy - $headR * 0.20
            $g.FillEllipse(
                $fill,
                [single]($cx - $headR),
                [single]($headCy - $headR),
                [single]($headR * 2),
                [single]($headR * 2))

            $stemTop = $headCy + $headR * 0.55
            $stemBot = $headCy + $headR * 2.20
            $stemTopHalfW = $headR * 0.45
            $stemBotHalfW = $headR * 0.85

            $pts = [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF([single]($cx - $stemTopHalfW), [single]$stemTop)),
                (New-Object System.Drawing.PointF([single]($cx + $stemTopHalfW), [single]$stemTop)),
                (New-Object System.Drawing.PointF([single]($cx + $stemBotHalfW), [single]$stemBot)),
                (New-Object System.Drawing.PointF([single]($cx - $stemBotHalfW), [single]$stemBot)))
            $g.FillPolygon($fill, $pts)
        } finally { $fill.Dispose() }
    } finally {
        $g.Dispose()
    }
    return $bmp
}

# 1. Render each icon size into a PNG byte buffer.
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()
foreach ($s in $sizes) {
    $bmp = New-MarkBitmap $s
    $ms = New-Object System.IO.MemoryStream
    try {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs += ,@{ Size = $s; Bytes = $ms.ToArray() }
    } finally {
        $ms.Dispose()
        $bmp.Dispose()
    }
}

# 2. Stitch ICONDIR + ICONDIRENTRY headers and PNG payloads into a single .ico.
$headerSize = 6 + (16 * $pngs.Count)
$out = New-Object System.IO.MemoryStream
$bw  = New-Object System.IO.BinaryWriter $out
try {
    $bw.Write([UInt16] 0)              # reserved
    $bw.Write([UInt16] 1)              # type = ICO
    $bw.Write([UInt16] $pngs.Count)    # image count

    $offset = $headerSize
    foreach ($p in $pngs) {
        $sz = $p.Size
        # Width and height are 1 byte each; 0 means 256.
        $bw.Write([Byte]   ($(if ($sz -eq 256) { 0 } else { $sz })))
        $bw.Write([Byte]   ($(if ($sz -eq 256) { 0 } else { $sz })))
        $bw.Write([Byte]   0)          # palette
        $bw.Write([Byte]   0)          # reserved
        $bw.Write([UInt16] 1)          # planes
        $bw.Write([UInt16] 32)         # bpp
        $bw.Write([UInt32] $p.Bytes.Length)
        $bw.Write([UInt32] $offset)
        $offset += $p.Bytes.Length
    }
    foreach ($p in $pngs) { $bw.Write($p.Bytes) }

    [System.IO.File]::WriteAllBytes($outIco, $out.ToArray())
} finally {
    $bw.Dispose()
}

Write-Host "Wrote $outIco ($($pngs.Count) sizes: $($sizes -join ', '))"
