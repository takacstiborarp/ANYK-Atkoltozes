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

# Ikon: sötét négyzet, alul egyenes narancs csík, fehér "Á". PNG-alapú ICO, több méretben.
function New-IkonPng([int]$m) {
    $bmp = New-Object Drawing.Bitmap $m, $m
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([Drawing.Color]::FromArgb(38, 38, 42))
    $csik = [Math]::Max(2, [int]($m / 8))
    $g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(230, 120, 30))), 0, $m - $csik, $m, $csik)
    $font = New-Object Drawing.Font('Segoe UI Semibold', [single]($m * 0.52), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('Á', $font, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, (-$m * 0.04), $m, ($m - $csik)), $sf)
    $g.Dispose()
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , $ms.ToArray()
}
$meretek = 16, 32, 48, 256
$kepek = foreach ($m in $meretek) { , (New-IkonPng $m) }
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
    'A telepítés végén a program elindítható. Később a Start menüből és az asztalról is elérhető.'
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
