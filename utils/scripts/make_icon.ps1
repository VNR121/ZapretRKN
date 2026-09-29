# make_icon.ps1 - generates icon.ico with multi-resolution
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function New-ZapretIcon {
    param([string]$OutputPath)

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

        # --- Круглая маска (для обрезки белого по границам шара) ---
        $circlePath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $circlePath.AddEllipse(0, 0, $size - 1, $size - 1)

        # --- Фон: приглушённый красный градиент ---
        $c1 = [System.Drawing.Color]::FromArgb(255, 185, 60, 65)
        $c2 = [System.Drawing.Color]::FromArgb(255, 70, 30, 38)
        $redBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0, 0)),
            (New-Object System.Drawing.Point(0, $size)),
            $c1, $c2
        )
        $g.FillEllipse($redBrush, 0, 0, $size - 1, $size - 1)

        # --- Белая область над синей линией ---
        # Работаем в повёрнутой на 135° системе — там линия горизонтальна.
        # Всё, что выше линии (y < 0), заливаем белым.
        $stripeThickness = [single]($size * 0.20)
        $state = $g.Save()
        $g.SetClip($circlePath)
        $center = [single]($size / 2)
        $g.TranslateTransform($center, $center)
        $g.RotateTransform(135)

        $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 235, 235, 240))
        # Прямоугольник: сверху от -1.5*size до границы линии (-thickness/2)
        $g.FillRectangle(
            $whiteBrush,
            [single](-$size * 1.5),
            [single](-$size * 1.5),
            [single]($size * 3),
            [single]($size * 1.5 - $stripeThickness / 2)
        )
        $g.Restore($state)

        # --- Внутренняя тень (объём) ---
        $innerBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($circlePath)
        $innerBrush.CenterColor = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
        $innerBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(47, 0, 0, 0))
        $g.FillEllipse($innerBrush, 0, 0, $size - 1, $size - 1)
        $innerBrush.Dispose()

        # --- Синяя диагональная полоса ---
        $state = $g.Save()
        $g.TranslateTransform($center, $center)
        $g.RotateTransform(135)
        $blueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(145, 70, 130, 200))
        $g.FillRectangle($blueBrush, [single](-$size * 1.5), [single](-$stripeThickness / 2), [single]($size * 3), $stripeThickness)
        $g.Restore($state)

        $blueBrush.Dispose()
        $whiteBrush.Dispose()
        $redBrush.Dispose()
        $circlePath.Dispose()
        $g.Dispose()

        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngDatas += ,$ms.ToArray()
        $ms.Dispose()
        $bmp.Dispose()
    }

    # --- Сборка .ico ---
    $fs = [System.IO.File]::Create($OutputPath)
    $bw = New-Object System.IO.BinaryWriter($fs)

    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]$sizes.Count)

    $offset = 6 + ($sizes.Count * 16)
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]
        $bw.Write([Byte]$(if ($s -ge 256) { 0 } else { $s }))
        $bw.Write([Byte]$(if ($s -ge 256) { 0 } else { $s }))
        $bw.Write([Byte]0)
        $bw.Write([Byte]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]32)
        $bw.Write([UInt32]$pngDatas[$i].Length)
        $bw.Write([UInt32]$offset)
        $offset += $pngDatas[$i].Length
    }

    foreach ($data in $pngDatas) {
        $bw.Write($data)
    }

    $bw.Flush()
    $bw.Close()
    $fs.Close()

    Write-Host "Icon created: $OutputPath"
}

$out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "icon.ico"
New-ZapretIcon -OutputPath $out