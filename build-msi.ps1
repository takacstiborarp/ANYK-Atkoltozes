#Requires -Version 5.1
<#
.SYNOPSIS
    MSI építése: dist\ANYK-Atkoltozes-<verzió>.msi
    Kell hozzá: WiX v5 (dotnet tool install --global wix) és a WixToolset.UI.wixext bővítmény.
#>
$ErrorActionPreference = 'Stop'
$Gyoker = $PSScriptRoot
Add-Type -AssemblyName System.Drawing

# A verzió a fő scriptből jön, így a kettő nem csúszhat szét.
$sor = Select-String -Path "$Gyoker\ANYK-Atkoltozes.ps1" -Pattern "^\`$Verzio = '([\d.]+)'" | Select-Object -First 1
if (-not $sor) { throw 'Nem találom a $Verzio sort az ANYK-Atkoltozes.ps1-ben.' }
$Verzio = $sor.Matches[0].Groups[1].Value
Write-Host "Verzió: $Verzio"

# A PowerShell 5.1 BOM nélkül rossz kódlappal olvasná az ékezeteket.
$bom = New-Object Text.UTF8Encoding $true
foreach ($f in 'ANYK-Atkoltozes.ps1', 'ANYK-Atkoltozes-GUI.ps1') {
    $p = Join-Path $Gyoker $f
    $b = [IO.File]::ReadAllBytes($p)
    if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
        [IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), $bom)
        Write-Host "BOM hozzáadva: $f"
    }
}

# ARP Hungary arculat
$Teal  = [Drawing.ColorTranslator]::FromHtml('#156366')
$Sotet = [Drawing.ColorTranslator]::FromHtml('#0A4343')
$Logo  = [Drawing.Image]::FromFile("$Gyoker\installer\arp_logo.png")
$Keszitette = 'Készítette: Takács Tibor - ARP Hungary Kft. +36 30 526-9886'

# A logó fehér változata (teal háttérre): a színt fehérre cseréljük, az átlátszóság marad.
function Get-FeherAttr {
    $cm = New-Object Drawing.Imaging.ColorMatrix
    $cm.Matrix00 = 0; $cm.Matrix11 = 0; $cm.Matrix22 = 0
    $cm.Matrix40 = 1; $cm.Matrix41 = 1; $cm.Matrix42 = 1
    $ia = New-Object Drawing.Imaging.ImageAttributes
    $ia.SetColorMatrix($cm)
    $ia
}
function Draw-Logo($g, [int]$x, [int]$y, [int]$m, [switch]$Feher) {
    $g.InterpolationMode = 'HighQualityBicubic'
    $r = New-Object Drawing.Rectangle $x, $y, $m, $m
    if ($Feher) { $g.DrawImage($Logo, $r, 0, 0, $Logo.Width, $Logo.Height, 'Pixel', (Get-FeherAttr)) }
    else { $g.DrawImage($Logo, $r) }
}

# Ikon: fehér négyzet, rajta az ARP-logó. A 256-os bejegyzés PNG, a kisebbek klasszikus 32 bites DIB,
# mert a GDI+ (Drawing.Icon) a PNG-s kis bejegyzéseket nem tudja kirajzolni.
function New-IkonKep([int]$m) {
    $bmp = New-Object Drawing.Bitmap $m, $m, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([Drawing.Color]::White)
    $marg = [Math]::Max(1, [int]($m * 0.1))
    Draw-Logo $g $marg $marg ($m - 2 * $marg)
    $g.Dispose()
    $ms = New-Object IO.MemoryStream
    if ($m -ge 256) {
        $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    } else {
        $w = New-Object IO.BinaryWriter $ms
        $w.Write([uint32]40); $w.Write([int32]$m); $w.Write([int32]($m * 2)); $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]0); $w.Write([uint32]($m * $m * 4)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
        for ($y = $m - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $m; $x++) {
                $c = $bmp.GetPixel($x, $y)
                $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A)
            }
        }
        $sor = [int]([Math]::Ceiling($m / 32.0) * 4)
        $w.Write((New-Object byte[] ($sor * $m)))
        $w.Flush()
    }
    $bmp.Dispose()
    , $ms.ToArray()
}

# Telepítendő logó: 128 px-es változat (a teljes felbontású csak a forrásban kell).
$kicsi = New-Object Drawing.Bitmap 128, 128
$g = [Drawing.Graphics]::FromImage($kicsi); $g.SmoothingMode = 'AntiAlias'; Draw-Logo $g 0 0 128; $g.Dispose()
$kicsi.Save("$Gyoker\installer\arp_logo_128.png", [Drawing.Imaging.ImageFormat]::Png); $kicsi.Dispose()

# A telepítő képei. Dialog: bal oldalon teal sáv fehér logóval és cégnévvel, jobbra fehér (ott a WixUI szövege).
$dlg = New-Object Drawing.Bitmap 493, 312
$g = [Drawing.Graphics]::FromImage($dlg)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([Drawing.Color]::White)
$g.FillRectangle((New-Object Drawing.SolidBrush $Teal), 0, 0, 164, 312)
Draw-Logo $g 42 44 80 -Feher
$sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'
$g.DrawString('ARP Hungary', (New-Object Drawing.Font('Segoe UI Semibold', 13)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 140, 164, 30), $sf)
$g.DrawString('ÁNYK átköltöztetés', (New-Object Drawing.Font('Segoe UI', 9)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 168, 164, 20), $sf)
$g.FillRectangle([Drawing.Brushes]::White, 32, 282, 100, 1)
$g.DrawString('arphungary.hu', (New-Object Drawing.Font('Segoe UI', 8)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 288, 164, 18), $sf)
$g.Dispose()
$dlg.Save("$Gyoker\installer\dialog.bmp", [Drawing.Imaging.ImageFormat]::Bmp); $dlg.Dispose()

# Banner: fehér, jobbra a logó, alul egyenes teal csík.
$ban = New-Object Drawing.Bitmap 493, 58
$g = [Drawing.Graphics]::FromImage($ban)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([Drawing.Color]::White)
Draw-Logo $g 437 9 40
$g.FillRectangle((New-Object Drawing.SolidBrush $Teal), 0, 56, 493, 2)
$g.Dispose()
$ban.Save("$Gyoker\installer\banner.bmp", [Drawing.Imaging.ImageFormat]::Bmp); $ban.Dispose()
$meretek = 16, 32, 48, 256
$kepek = foreach ($m in $meretek) { , (New-IkonKep $m) }
$ico = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $ico
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$meretek.Count)
$eltolas = 6 + 16 * $meretek.Count
for ($i = 0; $i -lt $meretek.Count; $i++) {
    $m = $meretek[$i]; $len = $kepek[$i].Length
    $w.Write([byte]($m % 256)); $w.Write([byte]($m % 256)); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$len); $w.Write([uint32]$eltolas)
    $eltolas += $len
}
foreach ($k in $kepek) { $w.Write($k) }
$w.Flush()
[IO.File]::WriteAllBytes("$Gyoker\installer\app.ico", $ico.ToArray())

# A telepítő első lapján látszó leírás (RTF, ékezetek \u escape-pel).
$szoveg = @(
    "ÁNYK átköltöztetés $Verzio",
    '',
    'Ez a program az Általános Nyomtatványkitöltő (ÁNYK, abevjava) gépcseréjét segíti.',
    '',
    'Mentés: a régi gépen ZIP-be menti a programot, a letöltött nyomtatványokat, a beállításokat és a mentett adatokat.',
    '',
    'Visszatöltés: az új gépen ellenőrzi a Javát és az ÁNYK-t, ha hiányzik, telepíti, majd a mentést a helyére teszi.',
    '',
    'A Java (Eclipse Temurin) a winget vagy az adoptium.net, az ÁNYK a nav.gov.hu oldaláról töltődik le, a saját licencfeltételeik szerint.',
    '',
    'A telepítés végén a program elindítható. Később a Start menüből és az asztalról is elérhető.',
    '',
    $Keszitette,
    'takacstibor@arphungary.hu, arphungary.hu'
)
$rtfTest = ($szoveg | ForEach-Object {
    $s = ($_.ToCharArray() | ForEach-Object {
        $c = [int]$_
        if ($c -gt 127) { "\u$c?" } elseif ($_ -in '\', '{', '}') { "\$_" } else { [string]$_ }
    }) -join ''
    "$s\par"
}) -join "`r`n"
$rtf = "{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\f0\fs18`r`n$rtfTest`r`n}"
[IO.File]::WriteAllText("$Gyoker\installer\leiras.rtf", $rtf, [Text.Encoding]::ASCII)

New-Item -ItemType Directory -Force -Path "$Gyoker\dist" | Out-Null
$msi = "$Gyoker\dist\ANYK-Atkoltozes-$Verzio.msi"
& wix build "$Gyoker\installer\ANYK-Atkoltozes.wxs" -arch x64 -ext WixToolset.UI.wixext -culture hu-HU `
    -d "Verzio=$Verzio" -d "Gyoker=$Gyoker" -o $msi
if ($LASTEXITCODE -ne 0) { throw "wix build hiba: $LASTEXITCODE" }
Remove-Item "$Gyoker\dist\*.wixpdb" -ErrorAction SilentlyContinue
Write-Host "Kész: $msi ($([math]::Round((Get-Item $msi).Length / 1KB)) KB)"
