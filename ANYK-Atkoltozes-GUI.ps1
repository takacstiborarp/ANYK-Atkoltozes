#Requires -Version 5.1
<#
.SYNOPSIS
    ÁNYK átköltöztetés, grafikus felület. Az ANYK-Atkoltozes.ps1-et hívja.
    Készítette: Takács Tibor - ARP Hungary Kft. +36 30 526-9886, takacstibor@arphungary.hu
#>
param(
    [ValidateSet('', 'Vissza')][string]$Mod = '',
    [string]$Profil = $env:USERPROFILE,
    [string]$Felhasznalo = $env:USERNAME
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$Core = Join-Path $PSScriptRoot 'ANYK-Atkoltozes.ps1'
. $Core -Konyvtar -Profil $Profil -Felhasznalo $Felhasznalo

# Háttérfolyamat futtatása, a kimenet sorai egy szálbiztos sorba kerülnek.
if (-not ('AnykFuttato' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Collections.Concurrent;
using System.Text;
using System.Runtime.InteropServices;
public class AnykFuttato {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public ConcurrentQueue<string> Sorok = new ConcurrentQueue<string>();
    public Process P;
    public void Indit(string exe, string args) {
        var psi = new ProcessStartInfo(exe, args);
        psi.UseShellExecute = false;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.CreateNoWindow = true;
        psi.StandardOutputEncoding = Encoding.UTF8;
        psi.StandardErrorEncoding = Encoding.UTF8;
        P = new Process();
        P.StartInfo = psi;
        P.OutputDataReceived += (s, e) => { if (e.Data != null) Sorok.Enqueue(e.Data); };
        P.ErrorDataReceived += (s, e) => { if (e.Data != null && e.Data.Trim().Length > 0) Sorok.Enqueue("[HIBA] " + e.Data); };
        P.Start();
        P.BeginOutputReadLine();
        P.BeginErrorReadLine();
    }
}
'@
}

# --- Megjelenés ---
$Betu      = New-Object Drawing.Font('Segoe UI', 10)
$BetuCim   = New-Object Drawing.Font('Segoe UI Semibold', 16)
$BetuAlcim = New-Object Drawing.Font('Segoe UI Semibold', 11)
$BetuNaplo = New-Object Drawing.Font('Consolas', 9)
# ARP Hungary arculat (ugyanaz a paletta, mint az ARP-jelentéseken)
$Hatter    = [Drawing.Color]::White
$Teal      = [Drawing.ColorTranslator]::FromHtml('#156366')
$Sotet     = [Drawing.ColorTranslator]::FromHtml('#0A4343')
$Tinta     = [Drawing.ColorTranslator]::FromHtml('#1B2A30')
$Szurke    = [Drawing.ColorTranslator]::FromHtml('#5C6B73')
$Vonal     = [Drawing.ColorTranslator]::FromHtml('#C9D3D7')
$Halvany   = [Drawing.ColorTranslator]::FromHtml('#F2F7F7')
$Zold      = $Teal
$Narancs   = [Drawing.ColorTranslator]::FromHtml('#A8681B')
$Piros     = [Drawing.ColorTranslator]::FromHtml('#8A2B2B')
$Keszitette = 'Készítette: Takács Tibor - ARP Hungary Kft. +36 30 526-9886'
$Email      = 'takacstibor@arphungary.hu'
$BetuLab    = New-Object Drawing.Font('Segoe UI', 8.5)

function Find-Eszkoz([string]$nev) {
    foreach ($p in (Join-Path $PSScriptRoot $nev), (Join-Path $PSScriptRoot "installer\$nev")) {
        if (Test-Path $p) { return $p }
    }
    $null
}

function New-Gomb([string]$szoveg, [int]$x, [int]$y, [int]$w = 120, [switch]$Fo) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $szoveg; $b.Location = "$x,$y"; $b.Size = "$w,32"; $b.Font = $Betu
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
    if ($Fo) {
        $b.BackColor = $Teal; $b.ForeColor = 'White'; $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $Sotet
    } else {
        $b.BackColor = 'White'; $b.ForeColor = $Tinta; $b.FlatAppearance.BorderColor = $Vonal
        $b.FlatAppearance.MouseOverBackColor = $Halvany
    }
    $b
}
function New-Cimke([string]$szoveg, [int]$x, [int]$y, [int]$w = 560, $font = $Betu, $szin = $null) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $szoveg; $l.Location = "$x,$y"; $l.Size = "$w,24"; $l.Font = $font
    if ($szin) { $l.ForeColor = $szin }
    $l
}
function New-Mezo([int]$x, [int]$y, [int]$w = 440) {
    $t = New-Object Windows.Forms.TextBox
    $t.Location = "$x,$y"; $t.Size = "$w,28"; $t.Font = $Betu
    $t
}
function New-Panel {
    $p = New-Object Windows.Forms.Panel
    $p.Location = '0,76'; $p.Size = '640,330'; $p.Visible = $false
    $form.Controls.Add($p)
    $p
}

$form = New-Object Windows.Forms.Form
$form.Text = 'ÁNYK átköltöztetés'
$form.ClientSize = '640,676'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $Hatter
$form.ForeColor = $Tinta
$form.Font = $Betu
$ikon = Find-Eszkoz 'app.ico'
if ($ikon) { $form.Icon = New-Object Drawing.Icon $ikon }

# --- Fejléc: ARP logó, cégnév, programnév, alatta egyenes teal csík ---
$logo = Find-Eszkoz 'arp_logo.png'
if ($logo) {
    $pb = New-Object Windows.Forms.PictureBox
    $pb.Image = [Drawing.Image]::FromFile($logo)
    $pb.SizeMode = 'Zoom'; $pb.Location = '24,16'; $pb.Size = '44,44'
    $form.Controls.Add($pb)
}
$form.Controls.Add((New-Cimke 'ARP Hungary' 80 15 400 (New-Object Drawing.Font('Segoe UI Semibold', 13)) $Sotet))
$form.Controls.Add((New-Cimke 'ÁNYK átköltöztetés' 81 40 400 $Betu $Szurke))
$csik = New-Object Windows.Forms.Panel
$csik.Location = '0,74'; $csik.Size = '640,2'; $csik.BackColor = $Teal
$form.Controls.Add($csik)

# --- Napló és állapotsor (a mentés és a visszatöltés lapon) ---
$naplo = New-Object Windows.Forms.TextBox
$naplo.Multiline = $true; $naplo.ReadOnly = $true; $naplo.ScrollBars = 'Vertical'
$naplo.Location = '24,412'; $naplo.Size = '592,160'; $naplo.Font = $BetuNaplo
$naplo.BackColor = $Halvany; $naplo.ForeColor = $Tinta; $naplo.BorderStyle = 'FixedSingle'
$form.Controls.Add($naplo)

# Folyamatjelző: egyenes sáv, benne egy mozgó teal blokk (a Windows zöld sávja helyett).
$sav = New-Object Windows.Forms.Panel
$sav.Location = '24,580'; $sav.Size = '592,3'; $sav.BackColor = $Halvany
$savBlokk = New-Object Windows.Forms.Panel
$savBlokk.Size = '120,3'; $savBlokk.BackColor = $Teal; $savBlokk.Visible = $false
$sav.Controls.Add($savBlokk)
$form.Controls.Add($sav)
$savIdozito = New-Object Windows.Forms.Timer
$savIdozito.Interval = 25
$savIdozito.Add_Tick({
    $x = $savBlokk.Left + 6
    if ($x -gt $sav.Width) { $x = -$savBlokk.Width }
    $savBlokk.Left = $x
})
function Start-Sav { $savBlokk.Left = -$savBlokk.Width; $savBlokk.Visible = $true; $savIdozito.Start() }
function Stop-Sav  { $savIdozito.Stop(); $savBlokk.Visible = $false }

$allapot = New-Cimke '' 24 590 592 $Betu $Szurke
$form.Controls.Add($allapot)

# --- Lábléc: Készítette sor ---
$labVonal = New-Object Windows.Forms.Panel
$labVonal.Location = '24,636'; $labVonal.Size = '592,1'; $labVonal.BackColor = $Vonal
$form.Controls.Add($labVonal)
$form.Controls.Add((New-Cimke $Keszitette 24 644 400 $BetuLab $Szurke))
$lEmail = New-Cimke $Email 416 644 200 $BetuLab $Szurke
$lEmail.TextAlign = 'TopRight'
$form.Controls.Add($lEmail)

function Naplo([string]$s) { $naplo.AppendText($s + "`r`n") }

# --- Háttérfeladat futtatása ---
$script:futo = $null
$script:utana = $null
$idozito = New-Object Windows.Forms.Timer
$idozito.Interval = 150
$idozito.Add_Tick({
    if (-not $script:futo) { return }
    $sor = $null
    while ($script:futo.Sorok.TryDequeue([ref]$sor)) { Naplo $sor }
    if ($script:futo.P.HasExited) {
        $script:futo.P.WaitForExit()
        while ($script:futo.Sorok.TryDequeue([ref]$sor)) { Naplo $sor }
        $kod = $script:futo.P.ExitCode
        $script:futo = $null
        $idozito.Stop()
        Stop-Sav
        $form.UseWaitCursor = $false
        if ($script:utana) { & $script:utana $kod }
    }
})

function Start-Feladat([string[]]$argumentumok, [scriptblock]$utana) {
    $naplo.Clear()
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Core`"") + $argumentumok +
         @('-Profil', "`"$Profil`"", '-Felhasznalo', "`"$Felhasznalo`"", '-Gui')
    $script:utana = $utana
    $script:futo = New-Object AnykFuttato
    Start-Sav
    $form.UseWaitCursor = $true
    $script:futo.Indit("$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe", ($a -join ' '))
    $idozito.Start()
}

# ======================================================================
# 1. Kezdőlap
# ======================================================================
$pStart = New-Panel
$pStart.Controls.Add((New-Cimke 'Mit szeretnél csinálni?' 24 24 560 $BetuCim))
$pStart.Controls.Add((New-Cimke 'Mentés a régi gépen, visszatöltés az új gépen.' 24 64 560 $Betu $Szurke))

$bMentesValaszt = New-Gomb 'Mentés' 24 110 280 -Fo
$bMentesValaszt.Height = 56
$pStart.Controls.Add($bMentesValaszt)
$pStart.Controls.Add((New-Cimke 'Erről a gépről ZIP-be mented az ÁNYK-t, a nyomtatványokat és az adatokat.' 24 172 300 $Betu $Szurke))
$pStart.Controls[$pStart.Controls.Count - 1].Height = 48

$bVisszaValaszt = New-Gomb 'Visszatöltés' 336 110 280 -Fo
$bVisszaValaszt.Height = 56
$pStart.Controls.Add($bVisszaValaszt)
$pStart.Controls.Add((New-Cimke 'Erre a gépre telepíted a Javát és az ÁNYK-t, ha kell, és visszatöltöd a mentést.' 336 172 280 $Betu $Szurke))
$pStart.Controls[$pStart.Controls.Count - 1].Height = 48

# ======================================================================
# 2. Mentés
# ======================================================================
$pMentes = New-Panel
$pMentes.Controls.Add((New-Cimke 'Mentés' 24 24 560 $BetuCim))
$pMentes.Controls.Add((New-Cimke 'Hol van most az ÁNYK programmappája (abevjava)?' 24 72 560 $BetuAlcim))
$tProg = New-Mezo 24 100
$pMentes.Controls.Add($tProg)
$bProg = New-Gomb 'Tallózás' 476 98 140
$pMentes.Controls.Add($bProg)
$lProgInfo = New-Cimke '' 24 130 592 $Betu $Szurke
$pMentes.Controls.Add($lProgInfo)

$pMentes.Controls.Add((New-Cimke 'Hova kerüljön a ZIP?' 24 168 560 $BetuAlcim))
$tCel = New-Mezo 24 196
$pMentes.Controls.Add($tCel)
$bCel = New-Gomb 'Tallózás' 476 194 140
$pMentes.Controls.Add($bCel)
$pMentes.Controls.Add((New-Cimke 'Pendrive vagy hálózati mappa a legjobb, hogy az új gépen elérd.' 24 226 592 $Betu $Szurke))

$bMentesVissza = New-Gomb 'Vissza' 24 280 120
$pMentes.Controls.Add($bMentesVissza)
$bMentesIndit = New-Gomb 'Mentés indítása' 436 280 180 -Fo
$pMentes.Controls.Add($bMentesIndit)

function Update-ProgInfo {
    if (Test-AnykDir $tProg.Text) { $lProgInfo.Text = 'ÁNYK programmappa rendben.'; $lProgInfo.ForeColor = $Zold }
    elseif ($tProg.Text) { $lProgInfo.Text = 'Ebben a mappában nincs abevjava.jar.'; $lProgInfo.ForeColor = $Piros }
    else { $lProgInfo.Text = 'Nem találtam automatikusan. Tallózd ki a mappát.'; $lProgInfo.ForeColor = $Piros }
}
$tProg.Add_TextChanged({ Update-ProgInfo })

$bProg.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = 'Válaszd ki az ÁNYK programmappáját (abevjava)'
    if ($tProg.Text -and (Test-Path $tProg.Text)) { $d.SelectedPath = $tProg.Text }
    if ($d.ShowDialog($form) -eq 'OK') { $tProg.Text = $d.SelectedPath }
})
$bCel.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = 'Hova kerüljön a mentés ZIP-fájlja?'
    if ($tCel.Text -and (Test-Path $tCel.Text)) { $d.SelectedPath = $tCel.Text }
    if ($d.ShowDialog($form) -eq 'OK') { $tCel.Text = $d.SelectedPath }
})

$bMentesIndit.Add_Click({
    if (-not (Test-AnykDir $tProg.Text)) {
        [Windows.Forms.MessageBox]::Show($form, 'A megadott mappában nincs ÁNYK (abevjava.jar).', 'ÁNYK átköltöztetés', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $tCel.Text) {
        [Windows.Forms.MessageBox]::Show($form, 'Add meg, hova kerüljön a ZIP.', 'ÁNYK átköltöztetés', 'OK', 'Warning') | Out-Null
        return
    }
    $bMentesIndit.Enabled = $false; $bMentesVissza.Enabled = $false
    $allapot.Text = 'Mentés folyamatban. Ne zárd be az ablakot.'
    Start-Feladat @('-Mentes', '-ProgramDir', "`"$($tProg.Text.TrimEnd('\'))`"", '-Cel', "`"$($tCel.Text.TrimEnd('\'))`"") {
        param($kod)
        $bMentesIndit.Enabled = $true; $bMentesVissza.Enabled = $true
        if ($kod -eq 0) {
            $allapot.Text = 'Kész. A ZIP-et vidd át az új gépre.'; $allapot.ForeColor = $Zold
            if ([Windows.Forms.MessageBox]::Show($form, "A mentés elkészült.`r`n`r`nMegnyissam a mappát?", 'ÁNYK átköltöztetés', 'YesNo', 'Information') -eq 'Yes') {
                Start-Process explorer.exe $tCel.Text
            }
        } else {
            $allapot.Text = 'A mentés nem sikerült. A részletek fent a naplóban.'; $allapot.ForeColor = $Piros
        }
    }
})

# ======================================================================
# 3. Visszatöltés
# ======================================================================
$pVissza = New-Panel
$pVissza.Controls.Add((New-Cimke 'Visszatöltés' 24 24 560 $BetuCim))

$pVissza.Controls.Add((New-Cimke '1. Java és ÁNYK ezen a gépen' 24 72 560 $BetuAlcim))
$lJava = New-Cimke 'Java: ellenőrzés...' 40 100 380
$lJava.AutoEllipsis = $true
$pVissza.Controls.Add($lJava)
$lAnyk = New-Cimke 'ÁNYK: ellenőrzés...' 40 124 380
$lAnyk.AutoEllipsis = $true
$pVissza.Controls.Add($lAnyk)
$tipp = New-Object Windows.Forms.ToolTip
$lJava.Add_TextChanged({ $tipp.SetToolTip($lJava, $lJava.Text) })
$lAnyk.Add_TextChanged({ $tipp.SetToolTip($lAnyk, $lAnyk.Text) })
$bTelepit = New-Gomb 'Hiányzók telepítése' 436 96 180 -Fo
$bTelepit.Visible = $false
$pVissza.Controls.Add($bTelepit)

$pVissza.Controls.Add((New-Cimke '2. A mentés (ZIP) kiválasztása' 24 168 560 $BetuAlcim))
$tZip = New-Mezo 24 196
$pVissza.Controls.Add($tZip)
$bZip = New-Gomb 'Tallózás' 476 194 140
$pVissza.Controls.Add($bZip)
$lZipInfo = New-Cimke '' 24 226 592 $Betu $Szurke
$pVissza.Controls.Add($lZipInfo)

$bVisszaVissza = New-Gomb 'Vissza' 24 280 120
$pVissza.Controls.Add($bVisszaVissza)
$bVisszaIndit = New-Gomb 'Visszatöltés indítása' 436 280 180 -Fo
$pVissza.Controls.Add($bVisszaIndit)

function Set-Lepes2([bool]$be) {
    $tZip.Enabled = $be; $bZip.Enabled = $be; $bVisszaIndit.Enabled = $be
}

function Update-Allapot {
    $prog = Find-AnykDir
    $javaw = Find-Javaw $prog
    if ($javaw) { $lJava.Text = "Java: megvan ($javaw)"; $lJava.ForeColor = $Zold }
    else { $lJava.Text = 'Java: nincs a gépen, telepíteni kell'; $lJava.ForeColor = $Piros }
    if ($prog) { $lAnyk.Text = "ÁNYK: megvan ($prog)"; $lAnyk.ForeColor = $Zold }
    else { $lAnyk.Text = 'ÁNYK: nincs a gépen, telepíteni kell'; $lAnyk.ForeColor = $Piros }
    [bool]($javaw -and $prog)
}

function Invoke-Telepites {
    $bTelepit.Enabled = $false; $bVisszaVissza.Enabled = $false
    Set-Lepes2 $false
    $allapot.Text = 'Telepítés folyamatban (Java, ÁNYK). Ez pár percig tarthat.'; $allapot.ForeColor = $Szurke
    Start-Feladat @('-Telepites') {
        param($kod)
        $bVisszaVissza.Enabled = $true
        $kesz = Update-Allapot
        if ($kod -eq 0 -or $kesz) {
            $bTelepit.Visible = $false
            $allapot.Text = 'A gép kész. Válaszd ki a mentést.'; $allapot.ForeColor = $Zold
            Set-Lepes2 $true
        } elseif ($kod -eq 3) {
            $bTelepit.Visible = $false
            $lAnyk.Text = 'ÁNYK: a mentésből települ a visszatöltéskor'; $lAnyk.ForeColor = $Narancs
            $allapot.Text = 'A NAV-telepítő nem érhető el. Az ÁNYK a mentésből települ.'; $allapot.ForeColor = $Narancs
            Set-Lepes2 $true
        } else {
            $bTelepit.Enabled = $true
            $allapot.Text = 'A telepítés nem sikerült. A részletek fent a naplóban.'; $allapot.ForeColor = $Piros
        }
    }
}
$bTelepit.Add_Click({ Invoke-Telepites })

$bZip.Add_Click({
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Title = 'Válaszd ki az ÁNYK-mentést'
    $d.Filter = 'ÁNYK-mentés (ANYK-mentes-*.zip)|ANYK-mentes-*.zip|Minden ZIP (*.zip)|*.zip'
    if ($d.ShowDialog($form) -eq 'OK') { $tZip.Text = $d.FileName }
})
$tZip.Add_TextChanged({
    $lZipInfo.ForeColor = $Szurke; $lZipInfo.Text = ''
    if (-not (Test-Path -LiteralPath $tZip.Text -PathType Leaf)) { return }
    try {
        $m = Read-Manifest $tZip.Text
        $lZipInfo.Text = "Mentés: $($m.Gep) gép, $($m.Felhasznalo) felhasználó, $($m.Datum -replace 'T', ' ')"
        $lZipInfo.ForeColor = $Zold
    } catch { $lZipInfo.Text = 'Ez a fájl nem ÁNYK-mentés.'; $lZipInfo.ForeColor = $Piros }
})

$bVisszaIndit.Add_Click({
    if ($lZipInfo.ForeColor -ne $Zold) {
        [Windows.Forms.MessageBox]::Show($form, 'Válassz ki egy ÁNYK-mentést (ANYK-mentes-*.zip).', 'ÁNYK átköltöztetés', 'OK', 'Warning') | Out-Null
        return
    }
    if (Test-AnykFut) {
        [Windows.Forms.MessageBox]::Show($form, 'Az ÁNYK most fut. Zárd be, aztán próbáld újra.', 'ÁNYK átköltöztetés', 'OK', 'Warning') | Out-Null
        return
    }
    Set-Lepes2 $false; $bVisszaVissza.Enabled = $false
    $allapot.Text = 'Visszatöltés folyamatban. Ne zárd be az ablakot.'; $allapot.ForeColor = $Szurke
    Start-Feladat @('-Visszatoltes', '-Archiv', "`"$($tZip.Text)`"") {
        param($kod)
        $bVisszaVissza.Enabled = $true; Set-Lepes2 $true
        Update-Allapot | Out-Null
        if ($kod -eq 0) {
            $allapot.Text = 'Kész. Az ÁNYK indítható az asztali parancsikonnal.'; $allapot.ForeColor = $Zold
            [Windows.Forms.MessageBox]::Show($form, "A visszatöltés elkészült.`r`n`r`nNyisd meg az ÁNYK-t, és ellenőrizz egy régi mentést.", 'ÁNYK átköltöztetés', 'OK', 'Information') | Out-Null
        } elseif ($kod -eq 4) {
            $allapot.Text = 'Kész, de figyelmeztetéssel. Nézd át a naplót ([FIGY] sorok).'; $allapot.ForeColor = $Narancs
            [Windows.Forms.MessageBox]::Show($form, "A visszatöltés lefutott, de volt figyelmeztetés.`r`n`r`nNézd át a naplót, aztán nyisd meg az ÁNYK-t, és ellenőrizz egy régi mentést.", 'ÁNYK átköltöztetés', 'OK', 'Warning') | Out-Null
        } else {
            $allapot.Text = 'A visszatöltés nem sikerült. A részletek fent a naplóban.'; $allapot.ForeColor = $Piros
        }
    }
})

# ======================================================================
# Navigáció
# ======================================================================
function Show-Panel($p) {
    foreach ($x in $pStart, $pMentes, $pVissza) { $x.Visible = ($x -eq $p) }
    $naplo.Visible = $sav.Visible = ($p -ne $pStart)
    $allapot.Text = ''; $allapot.ForeColor = $Szurke
}

function Enter-Vissza {
    Show-Panel $pVissza
    $naplo.Clear()
    Set-Lepes2 $false
    if (Update-Allapot) {
        $allapot.Text = 'A Java és az ÁNYK megvan. Válaszd ki a mentést.'; $allapot.ForeColor = $Zold
        Set-Lepes2 $true
    } else {
        $bTelepit.Visible = $true
        Invoke-Telepites
    }
}

$bMentesValaszt.Add_Click({
    Show-Panel $pMentes
    $naplo.Clear()
    if (-not $tProg.Text) { $tProg.Text = Find-AnykDir }
    Update-ProgInfo
    if (-not $tCel.Text) { $tCel.Text = [Environment]::GetFolderPath('Desktop') }
})

$bVisszaValaszt.Add_Click({
    if (-not (Test-Admin)) {
        # Emelt joggal indul újra, de a felhasználói adatok a mostani felhasználó profiljába kerülnek.
        try {
            $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Mod Vissza -Profil `"$Profil`" -Felhasznalo `"$Felhasznalo`""
            Start-Process powershell.exe -Verb RunAs -ArgumentList $a | Out-Null
            $form.Close()
        } catch {
            [Windows.Forms.MessageBox]::Show($form, 'A visszatöltéshez rendszergazdai jog kell (Java és ÁNYK telepítése).', 'ÁNYK átköltöztetés', 'OK', 'Warning') | Out-Null
        }
        return
    }
    Enter-Vissza
})

$bMentesVissza.Add_Click({ Show-Panel $pStart; $naplo.Clear() })
$bVisszaVissza.Add_Click({ Show-Panel $pStart; $naplo.Clear() })

$form.Add_FormClosing({
    param($s, $e)
    if ($script:futo) {
        $v = [Windows.Forms.MessageBox]::Show($form, 'Egy művelet még fut. Biztosan kilépsz?', 'ÁNYK átköltöztetés', 'YesNo', 'Warning')
        if ($v -ne 'Yes') { $e.Cancel = $true }
    }
})

$form.Add_Shown({
    # Ha az indító rejtett vagy kis ablakot kért (parancsikon, -WindowStyle Hidden), a Windows az első
    # ShowWindow hívásra azt alkalmazza. Ezért itt kényszerítjük a normál megjelenést.
    [void][AnykFuttato]::ShowWindow($form.Handle, 1)
    [void][AnykFuttato]::SetForegroundWindow($form.Handle)
    if ($Mod -eq 'Vissza') { Enter-Vissza } else { Show-Panel $pStart }
    $form.Activate()
})

[void]$form.ShowDialog()
