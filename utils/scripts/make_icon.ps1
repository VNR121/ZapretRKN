# make_icon.ps1 - generates icon.ico and icon_grey.ico
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function New-ZapretIcon {
    param(
        [string]$OutputPath,
        [switch]$Grey
    )

    if ($Grey) {
        $topColor    = [System.Drawing.Color]::FromArgb(255, 210, 210, 215)
        $bg1         = [System.Drawing.Color]::FromArgb(255, 120, 120, 125)
        $bg2         = [System.Drawing.Color]::FromArgb(255, 55, 55, 60)
        $stripeColor = [System.Drawing.Color]::FromArgb(195, 80, 80, 90)
    } else {
        $topColor    = [System.Drawing.Color]::FromArgb(255, 225, 225, 240)
        $bg1         = [System.Drawing.Color]::FromArgb(255, 185, 60, 65)
        $bg2         = [System.Drawing.Color]::FromArgb(255, 70, 30, 38)
        $stripeColor = [System.Drawing.Color]::FromArgb(195, 10, 10, 221)
    }

    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngDatas = @()

    foreach ($size in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bmp.SetResolution(96, 96)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)

        $circlePath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $circlePath.AddEllipse(0, 0, $size - 1, $size - 1)

        $redBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0, 0)),
            (New-Object System.Drawing.Point(0, $size)),
            $bg1, $bg2
        )
        $g.FillEllipse($redBrush, 0, 0, $size - 1, $size - 1)

        $stripeThickness = [single]($size * 0.25)
        $state = $g.Save()
        $g.SetClip($circlePath)
        $center = [single]($size / 2)
        $g.TranslateTransform($center, $center)
        $g.RotateTransform(135)

        $topBrush = New-Object System.Drawing.SolidBrush($topColor)
        $g.FillRectangle(
            $topBrush,
            [single](-$size * 1.5),
            [single]($stripeThickness / 2),
            [single]($size * 3),
            [single]($size * 1.5)
        )
        $g.Restore($state)

        $innerBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($circlePath)
        $innerBrush.CenterColor = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
        $innerBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(25, 0, 0, 0))
        $g.FillEllipse($innerBrush, 0, 0, $size - 1, $size - 1)
        $innerBrush.Dispose()

        $state = $g.Save()
        $g.TranslateTransform($center, $center)
        $g.RotateTransform(135)
        $stripeBrush = New-Object System.Drawing.SolidBrush($stripeColor)
        $g.FillRectangle($stripeBrush, [single](-$size * 1.5), [single](-$stripeThickness / 2), [single]($size * 3), $stripeThickness)
        $g.Restore($state)

        $stripeBrush.Dispose()
        $topBrush.Dispose()
        $redBrush.Dispose()
        $circlePath.Dispose()
        $g.Dispose()

        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngDatas += ,$ms.ToArray()
        $ms.Dispose()
        $bmp.Dispose()
    }

    $fs = [System.IO.File]::Create($OutputPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
    $offset = 6 + ($sizes.Count * 16)
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]
        $bw.Write([Byte]$(if ($s -ge 256) { 0 } else { $s }))
        $bw.Write([Byte]$(if ($s -ge 256) { 0 } else { $s }))
        $bw.Write([Byte]0); $bw.Write([Byte]0)
        $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]$pngDatas[$i].Length)
        $bw.Write([UInt32]$offset)
        $offset += $pngDatas[$i].Length
    }
    foreach ($data in $pngDatas) { $bw.Write($data) }
    $bw.Flush(); $bw.Close(); $fs.Close()
    Write-Host "Icon created: $OutputPath"
}

$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition
New-ZapretIcon -OutputPath (Join-Path $dir "icon.ico")
New-ZapretIcon -OutputPath (Join-Path $dir "icon_grey.ico") -Grey