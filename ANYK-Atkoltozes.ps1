#Requires -Version 5.1
<#
.SYNOPSIS
    ÁNYK (abevjava) átköltöztetése egyik gépről a másikra.
    Készítette: Takács Tibor - ARP Hungary Kft. +36 30 526-9886, takacstibor@arphungary.hu

.DESCRIPTION
    Mentés (régi gép):
      - megkeresi az ÁNYK program mappáját,
      - elmenti a programot a letöltött nyomtatványokkal együtt,
      - elmenti a felhasználói beállításokat (%USERPROFILE%\.abevjava),
      - elmenti a felhasználói adatokat (%USERPROFILE%\abevjava: mentések, kontroll, napló, KR-fájlok),
      - a beállításokban talált egyéb adatmappákat is (pl. D:\ANYK_mentesek),
      - mindezt egy ZIP-be teszi: ANYK-mentes-<gépnév>-<dátum>.zip

    Telepítés (új gép, a visszatöltés első lépése):
      - ellenőrzi a Javát, ha nincs, telepíti (winget, tartaléknak az Adoptium MSI),
      - ellenőrzi az ÁNYK-t, ha nincs, letölti a hivatalos NAV-telepítőt, és úgy bontja ki,
        ahogy a NAV telepítője (indítószkriptek, abevjavapath.cfg, parancsikon).

    Visszatöltés (új gép):
      - a telepítés lépéseit is elvégzi, ha valami hiányzik,
      - visszatölti a beállításokat és az adatokat,
      - átírja az útvonalakat, ha az új gépen más a felhasználónév vagy a mappa,
      - a végén ellenőrzi az eredményt.

.EXAMPLE
    .\ANYK-Atkoltozes.ps1 -Mentes
    .\ANYK-Atkoltozes.ps1 -Mentes -Cel E:\ -ExtraPath 'D:\Ugyfelek\ANYK'
    .\ANYK-Atkoltozes.ps1 -Telepites
    .\ANYK-Atkoltozes.ps1 -Visszatoltes
    .\ANYK-Atkoltozes.ps1 -Visszatoltes -Archiv E:\ANYK-mentes-REGIPC-20261110-0930.zip
#>
[CmdletBinding()]
param(
    [switch]$Mentes,
    [switch]$Telepites,
    [switch]$Visszatoltes,
    [string]$Archiv,
    [string]$Cel = $PSScriptRoot,
    [string[]]$ExtraPath = @(),
    [string]$Telepito,
    [string]$ProgramDir,
    [string]$Profil = $env:USERPROFILE,
    [string]$Felhasznalo = $env:USERNAME,
    [string]$JavaWingetId = 'EclipseAdoptium.Temurin.21.JRE',
    [switch]$NincsParancsikon,
    [switch]$Szunet,
    [switch]$Gui,
    [switch]$Konyvtar,
    [switch]$NagyMappa,
    [int]$NagyMappaMB = 1024
)

$Verzio = '1.3.0'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if ($Gui) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
$Ido = Get-Date -Format 'yyyyMMdd-HHmm'
$Profil = $Profil.TrimEnd('\')

$NavTelepitoUrl = 'https://nav.gov.hu/pfile/programFile?path=/nyomtatvanyok/letoltesek/nyomtatvanykitolto_programok/nyomtatvany_apeh/keretprogramok/AbevJava'
$AdoptiumMsiUrl = 'https://api.adoptium.net/v3/installer/latest/21/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk'
$AnykAlapDir    = Join-Path $env:ProgramFiles 'abevjava'
$PathCfg        = Join-Path $env:windir 'abevjavapath.cfg'

function Info($m) { Write-Host "[ANYK] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[FIGY] $m" -ForegroundColor Yellow }
function Vege([int]$kod) {
    if ($Szunet) { Read-Host 'Nyomj Entert a bezáráshoz' | Out-Null }
    exit $kod
}
function Fail($m) { Write-Host "[HIBA] $m" -ForegroundColor Red; Vege 1 }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-AnykDir([string]$d) {
    $d -and (Test-Path -LiteralPath $d -PathType Container) -and
        @(Get-ChildItem -LiteralPath $d -Filter 'abevjava*.jar' -File -ErrorAction SilentlyContinue).Count -gt 0
}

# A NAV-telepítő ide írja a programmappát: abevjava.path=C:\\Program Files\\abevjava
function Read-PathCfg([string]$f) {
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $sor = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*abevjava\.path\s*=' } | Select-Object -First 1
    if (-not $sor) { return $null }
    (($sor -split '=', 2)[1].Trim()) -replace '\\:', ':' -replace '\\\\', '\'
}

function Find-AnykDir([string]$Hint) {
    $c = @()
    if ($Hint) { $c += $Hint }
    $c += Read-PathCfg $PathCfg
    $c += Read-PathCfg (Join-Path $Profil '.abevjava\abevjavapath.cfg')
    $kulcsok = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($k in $kulcsok) {
        Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -match 'abevjava|nyomtatv.nykit|ANYK|ÁNYK' -and $p.InstallLocation) {
                $c += $p.InstallLocation
            }
        }
    }
    $c += "$env:ProgramFiles\abevjava", "${env:ProgramFiles(x86)}\abevjava", 'C:\abevjava', "$Profil\abevjava"
    foreach ($d in $c) {
        if (Test-AnykDir $d) { return (Resolve-Path -LiteralPath $d).Path.TrimEnd('\') }
    }
    return $null
}

function Find-Javaw([string]$prog) {
    if ($prog -and (Test-Path "$prog\jre\bin\javaw.exe")) { return "$prog\jre\bin\javaw.exe" }
    $c = Get-Command javaw.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\javaw.exe")) { return "$env:JAVA_HOME\bin\javaw.exe" }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $t = Get-ChildItem "$pf\*\*\bin\javaw.exe" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($t) { return $t.FullName }
    }
    return $null
}

function Install-Java {
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Info "Java telepítése wingettel: $JavaWingetId"
        & winget.exe install --id $JavaWingetId -e --silent --source winget --accept-package-agreements --accept-source-agreements | Out-Null
        $global:LASTEXITCODE = 0
        $j = Find-Javaw
        if ($j) { return $j }
        Warn 'A winget nem telepítette a Javát. Próbálom az Adoptium telepítőjével.'
    } else {
        Info 'Nincs winget. A Javát az Adoptium oldaláról töltöm le.'
    }
    $msi = Join-Path $env:TEMP "temurin-jre-$Ido.msi"
    Invoke-WebRequest -Uri $AdoptiumMsiUrl -OutFile $msi -UseBasicParsing
    # Csak érvényes digitális aláírású telepítőt futtatunk.
    $sig = Get-AuthenticodeSignature -FilePath $msi
    if ($sig.Status -ne 'Valid') {
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
        Warn "A letöltött Java-telepítő aláírása nem érvényes ($($sig.Status)). Nem telepítem."
        return $null
    }
    Info "Aláírás rendben: $($sig.SignerCertificate.Subject)"
    Info 'Java telepítése (Temurin JRE)...'
    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart',
         'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith' -Wait -PassThru
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -notin 0, 3010) { Warn "A Java telepítő hibakóddal állt le: $($p.ExitCode)" }
    Find-Javaw
}

# Ugyanazt csinálja, mint a NAV jarinstaller: az application\ mappát a programmappába bontja,
# megírja a setenv.bat-ot és az abevjava_start.bat-ot.
function Install-AnykNav([string]$cel) {
    $jar = Join-Path $env:TEMP "abevjava_install-$Ido.jar"
    Info 'A hivatalos ÁNYK-telepítő letöltése a NAV oldaláról...'
    Invoke-WebRequest -Uri $NavTelepitoUrl -OutFile $jar -UseBasicParsing -UserAgent 'Mozilla/5.0'
    $z = [IO.Compression.ZipFile]::OpenRead($jar)
    try {
        if (-not ($z.Entries | Where-Object FullName -eq 'application/abevjava.jar')) {
            throw 'A letöltött fájl nem ÁNYK-telepítő.'
        }
        Info "Kibontás ide: $cel"
        foreach ($e in $z.Entries) {
            if ($e.FullName.EndsWith('/')) { continue }
            if ($e.FullName.StartsWith('application/')) { $rel = $e.FullName.Substring(12) }
            elseif ($e.FullName.StartsWith('os/install/win/')) { $rel = $e.FullName.Substring(15) }
            else { continue }
            $dest = Join-Path $cel ($rel -replace '/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        }
    } finally { $z.Dispose(); Remove-Item $jar -Force -ErrorAction SilentlyContinue }

    foreach ($d in 'abev', 'abev\kontroll', 'segitseg', 'eroforrasok', 'nyomtatvanyok', 'nyomtatvanyok_archivum', 'upgrade') {
        New-Item -ItemType Directory -Force -Path (Join-Path $cel $d) | Out-Null
    }
    $utf8 = New-Object Text.UTF8Encoding $false
    $setenv = Join-Path $cel 'setenv.bat'
    if (-not (Test-Path $setenv)) {
        [IO.File]::WriteAllText($setenv, "@REM ECHO OFF`r`n@SET MEMORY_OPTS=-Xms128m -Xmx256m`r`n@SET TUNING_OPTS=`r`n", $utf8)
    }
    # Ugyanazok az indítószkriptek, mint a NAV jarinstaller.xml-jében (Windows rész).
    $opt  = '-XX:+IgnoreUnrecognizedVMOptions --add-modules=java.se.ee'
    $boot = "@CALL .\setenv.bat`r`n@%ABEV_JAVA_HOME%java $opt %MEMORY_OPTS% -jar boot.jar`r`n"
    $hl   = "@%ABEV_JAVA_HOME%java $opt %MEMORY_OPTS% %TUNING_OPTS% -Djava.awt.headless=true -DentityExpansionLimit=128000 -jar abevjava.jar cfg=cfg.enyk"
    $bat = [ordered]@{
        'abevjava_start'       = "@IF EXIST `"$cel/jre/bin/`" (SET ABEV_JAVA_HOME=`"$cel/jre/bin/`")`r`n" + $boot +
                                 "@%ABEV_JAVA_HOME%java $opt %MEMORY_OPTS% %TUNING_OPTS% %RUN_OPTS% -DentityExpansionLimit=128000 -jar abevjava.jar cfg=cfg.enyk %1 %2 %3`r`n"
        'abevjava_instnew'     = $boot + "$hl cmd:`"instnew.silent`"`r`n"
        'abevjava_instupdate'  = $boot + "$hl cmd:`"instupgrade.silent`"`r`n"
        'abevjava_replicate'   = $boot + "$hl cmd:`"replicate.silent`"`r`n"
        'abevjava_start_new'   = "call abevjava_start cmd:`"file.new %1`"`r`n"
        'abevjava_start_open'  = "call abevjava_start cmd:`"file.open %1`"`r`n"
        'abevjava_start_test'  = "call abevjava_start_new %1`r`n"
    }
    foreach ($n in $bat.Keys) { [IO.File]::WriteAllText((Join-Path $cel "$n.bat"), $bat[$n], $utf8) }
    [IO.File]::WriteAllText((Join-Path $cel 'abevjava_start_import.bat'),
        "@cscript `"$cel/gen_abevjava_import.vbs`" %1 `"$cel/abevjava.jar`"`r`n", [Text.Encoding]::GetEncoding(28592))
}

function Set-AnykPathCfg([string]$prog) {
    $most = Read-PathCfg $PathCfg
    if ($most -and ($most.TrimEnd('\') -ieq $prog) ) { return }
    if ($most -and (Test-AnykDir $most)) { Warn "Az abevjavapath.cfg másik ÁNYK-ra mutat: $most. Nem írom át."; return }
    $ertek = $prog.Substring(0, 2) + ($prog.Substring(2) -replace '\\', '\\')
    # Ha a Windows mappa nem írható, a NAV-telepítő is a felhasználó .abevjava mappáját használja.
    foreach ($f in $PathCfg, (Join-Path $Profil '.abevjava\abevjavapath.cfg')) {
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
            [IO.File]::WriteAllText($f, "abevjava.path=$ertek`r`n", [Text.Encoding]::GetEncoding(28591))
            Ok "abevjavapath.cfg: $f"
            return
        } catch { Warn "Nem tudom írni: $f" }
    }
}

# A NAV indítószkriptje --add-modules=java.se.ee kapcsolóval indul. Ha a Java ezt nem fogadja el,
# a kapcsolót kivesszük, különben az ÁNYK nem indul.
function Repair-AddModules([string]$prog, [string]$javaw) {
    $java = Join-Path (Split-Path $javaw) 'java.exe'
    & cmd.exe /c "`"$java`" -XX:+IgnoreUnrecognizedVMOptions --add-modules=java.se.ee -version >nul 2>&1"
    $rc = $LASTEXITCODE; $global:LASTEXITCODE = 0
    if ($rc -eq 0) { return }
    $elso = $true
    Get-ChildItem -LiteralPath $prog -Filter 'abevjava_*.bat' -File | ForEach-Object {
        $t = [IO.File]::ReadAllText($_.FullName)
        if ($t -match '--add-modules=java\.se\.ee') {
            if ($elso) { Warn 'Ez a Java nem ismeri a java.se.ee modult. Kiveszem a kapcsolót az indítószkriptekből.'; $elso = $false }
            Copy-Item -LiteralPath $_.FullName -Destination "$($_.FullName).elotte-$Ido" -Force
            [IO.File]::WriteAllText($_.FullName, ($t -replace ' ?--add-modules=java\.se\.ee', ''), (New-Object Text.UTF8Encoding $false))
            Ok "Javítva: $($_.Name)"
        }
    }
}

# Az indítószkript a PATH-ban keresi a javát. Ha a Java nincs a PATH-ban (és nincs saját jre a
# programmappában), a setenv.bat-ba beírjuk a helyét, különben az ÁNYK nem indulna.
function Test-JavaPathon {
    $utak = ([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
             [Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_ }
    foreach ($d in $utak) {
        $d = [Environment]::ExpandEnvironmentVariables($d.Trim('"'))
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'java.exe'))) { return $true }
    }
    $false
}

function Set-AbevJavaHome([string]$prog, [string]$javaw) {
    $setenv = Join-Path $prog 'setenv.bat'
    $jel = '@REM ANYK-Atkoltozes: a Java helye'
    $sorok = @()
    if (Test-Path -LiteralPath $setenv) {
        $sorok = @([IO.File]::ReadAllLines($setenv) | Where-Object { $_ -ne $jel -and $_ -notmatch '^@IF NOT DEFINED ABEV_JAVA_HOME SET ABEV_JAVA_HOME=.*ANYK-Atkoltozes' })
    }
    $kell = -not (Test-Path -LiteralPath "$prog\jre\bin\java.exe") -and -not (Test-JavaPathon)
    if ($kell) {
        $bin = Split-Path $javaw
        $sorok += $jel
        $sorok += "@IF NOT DEFINED ABEV_JAVA_HOME SET ABEV_JAVA_HOME=`"$bin\`"& REM ANYK-Atkoltozes"
    }
    $uj = ($sorok -join "`r`n") + "`r`n"
    $regi = if (Test-Path -LiteralPath $setenv) { [IO.File]::ReadAllText($setenv) } else { '' }
    if ($uj -ne $regi -and ($kell -or $regi -match 'ANYK-Atkoltozes')) {
        if ($regi) { Copy-Item -LiteralPath $setenv -Destination "$setenv.elotte-$Ido" -Force }
        [IO.File]::WriteAllText($setenv, $uj, (New-Object Text.UTF8Encoding $false))
        if ($kell) { Ok "A Java nincs a PATH-ban, a helyét beírtam: $setenv" }
    }
}

function Test-AnykFut {
    $p = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction SilentlyContinue |
         Where-Object { $_.CommandLine -match 'abevjava' }
    @($p).Count -gt 0
}

function Copy-Dir([string]$src, [string]$dst, [string[]]$extra = @()) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    & robocopy.exe $src $dst /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP @extra | Out-Null
    $rc = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($rc -ge 8) { throw "Másolási hiba (robocopy $rc): $src -> $dst" }
}

function Get-FileCount([string]$d) {
    if (-not (Test-Path -LiteralPath $d)) { return 0 }
    @(Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue).Count
}

function Get-DirSize([string]$d) {
    if (-not (Test-Path -LiteralPath $d)) { return 0 }
    $m = (Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($m) { [long]$m } else { 0 }
}

# Személyes gyűjtőmappák (Dokumentumok, Asztal, Letöltések, OneDrive…): ezeket egészben nem mentjük
# magától, mert az ÁNYK-n kívül minden más is bennük van.
function Get-TagMappak {
    $l = @($Profil)
    foreach ($n in 'Desktop', 'MyDocuments', 'MyPictures', 'MyMusic', 'MyVideos') { $l += [Environment]::GetFolderPath($n) }
    $l += (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue).'{374DE290-123F-4565-9164-39C4925E467B}'
    $l += $env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer
    $l | Where-Object { $_ } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') }
}

function Test-Under([string]$p, [string]$root) {
    if (-not $p -or -not $root) { return $false }
    $p = $p.TrimEnd('\') + '\'
    $root = $root.TrimEnd('\') + '\'
    $p.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
}

$Latin1 = [Text.Encoding]::GetEncoding(28591)

# Az .enyk beállításfájlokban szereplő mappák (pl. egyedi mentési hely).
function Get-EnykPaths([string[]]$dirs) {
    $out = @()
    foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -Recurse -Filter '*.enyk' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $t = [IO.File]::ReadAllText($_.FullName, $Latin1)
            foreach ($m in [regex]::Matches($t, '(?m)=\s*([A-Za-z])\\?:((?:\\\\|\\|/)[^\r\n]*)')) {
                $rest = $m.Groups[2].Value -replace '\\\\', '\' -replace '/', '\'
                $out += ($m.Groups[1].Value + ':' + $rest).Trim().TrimEnd('\')
            }
        }
    }
    $out | Sort-Object -Unique
}

# Útvonalak cseréje EGYETLEN menetben (sima, dupla backslash, perjel és Java-properties alak).
# Egymás utáni cserénél a már átírt szöveget a következő pár újra átírná:
# C:\Users\Tibor -> C:\Users\Tibor.Takacs után a profilcsere Tibor.Takacs.Takacs-ot csinálna.
# A régi útvonal után csak elválasztó jöhet, így a C:\Users\Tibor nem talál bele a C:\Users\Tibor2-be.
function Convert-Utak([string]$t, $map) {
    if (-not $t) { return $t }
    $parok = @{}
    foreach ($par in $map) {
        $old = ([string]$par[0]).TrimEnd('\'); $new = ([string]$par[1]).TrimEnd('\')
        if ($old.Length -lt 3 -or $old -ieq $new) { continue }
        $valt = @(
            @($old, $new),
            @(($old -replace '\\', '\\'), ($new -replace '\\', '\\')),
            @(($old -replace '\\', '/'), ($new -replace '\\', '/'))
        )
        if ($old -match '^[A-Za-z]:' -and $new -match '^[A-Za-z]:') {
            $valt += , @(($old.Substring(0, 1) + '\:' + ($old.Substring(2) -replace '\\', '\\')),
                         ($new.Substring(0, 1) + '\:' + ($new.Substring(2) -replace '\\', '\\')))
        }
        foreach ($v in $valt) { if (-not $parok.ContainsKey($v[0])) { $parok[$v[0]] = $v[1] } }
    }
    if ($parok.Count -eq 0) { return $t }
    $minta = ($parok.Keys | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $re = New-Object Text.RegularExpressions.Regex ("(?:$minta)(?![^\\/\r\n\t""';,=])", 'IgnoreCase')
    $re.Replace($t, [Text.RegularExpressions.MatchEvaluator]{ param($m) $parok[$m.Value] }.GetNewClosure())
}

# Útvonalak átírása a beállításfájlokban (.enyk, abevjavapath.cfg). Az eredetit megtartja.
function Update-Enyk([string[]]$files, $map) {
    foreach ($f in $files) {
        $t = [IO.File]::ReadAllText($f, $Latin1)
        $uj = Convert-Utak $t $map
        if ($uj -cne $t) {
            Copy-Item -LiteralPath $f -Destination "$f.elotte-$Ido" -Force
            [IO.File]::WriteAllText($f, $uj, $Latin1)
            Ok "Útvonalak átírva: $f"
        }
    }
}

function New-Parancsikon([string]$prog, [string]$javaw) {
    $sh = New-Object -ComObject WScript.Shell
    $indito = Join-Path $prog 'abevjava_start.bat'
    $jar = Join-Path $prog 'abevjava.jar'
    $helyek = @([Environment]::GetFolderPath('CommonDesktopDirectory'),
                (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'ÁNYK'))
    foreach ($h in $helyek) {
        New-Item -ItemType Directory -Force -Path $h | Out-Null
        $l = $sh.CreateShortcut((Join-Path $h 'ÁNYK.lnk'))
        if (Test-Path $indito) {
            $l.TargetPath = $indito
            $l.WindowStyle = 7
        } else {
            $l.TargetPath = $javaw
            $l.Arguments = "-jar `"$jar`" cfg=cfg.enyk"
        }
        $l.WorkingDirectory = $prog
        if (Test-Path "$prog\abevjava.ico") { $l.IconLocation = "$prog\abevjava.ico" }
        $l.Description = 'Általános Nyomtatványkitöltő'
        $l.Save()
        Ok "Parancsikon: $h\ÁNYK.lnk"
    }
}

function Read-Manifest([string]$zip) {
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $e = $z.GetEntry('manifest.json')
        if (-not $e) { throw "Ez nem ÁNYK-mentés (nincs manifest.json): $zip" }
        $r = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
        try { $r.ReadToEnd() | ConvertFrom-Json } finally { $r.Dispose() }
    } finally { $z.Dispose() }
}

function Invoke-Emelt([string[]]$modArgs) {
    Info 'Rendszergazdai jog kell (Java/ÁNYK telepítés). Újraindítás emelt joggal...'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $modArgs +
         @('-Profil', "`"$Profil`"", '-Felhasznalo', "`"$Felhasznalo`"", '-JavaWingetId', $JavaWingetId, '-Szunet')
    if ($ProgramDir)       { $a += '-ProgramDir', "`"$ProgramDir`"" }
    if ($NincsParancsikon) { $a += '-NincsParancsikon' }
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $a -Wait -PassThru
    exit $p.ExitCode
}

if ($Konyvtar) { return }

if ((@($Mentes, $Telepites, $Visszatoltes) | Where-Object { $_ }).Count -ne 1) {
    Write-Host "ÁNYK átköltöztetés $Verzio - ARP Hungary Kft."
    Write-Host 'Készítette: Takács Tibor - ARP Hungary Kft. +36 30 526-9886, takacstibor@arphungary.hu'
    Write-Host 'Használat:'
    Write-Host '  .\ANYK-Atkoltozes.ps1 -Mentes        (a régi gépen)'
    Write-Host '  .\ANYK-Atkoltozes.ps1 -Telepites     (az új gépen: Java + ÁNYK, ha hiányzik)'
    Write-Host '  .\ANYK-Atkoltozes.ps1 -Visszatoltes  (az új gépen)'
    Vege 2
}

# ======================================================================
# MENTÉS
# ======================================================================
if ($Mentes) {
    Info "Mentés indul. Gép: $env:COMPUTERNAME, profil: $Profil"
    $prog = Find-AnykDir $ProgramDir
    if (-not $prog) { Fail "Nem találom az ÁNYK-t. Add meg a mappáját: -ProgramDir 'C:\...\abevjava'" }
    Ok "ÁNYK program: $prog"
    if (Test-AnykFut) { Fail 'Az ÁNYK most fut. Zárd be, aztán indítsd újra a mentést.' }

    $tetelek = @([pscustomobject]@{ Nev = 'program'; Ut = $prog; Tipus = 'program' })

    $beall = Join-Path $Profil '.abevjava'
    if (Test-Path -LiteralPath $beall) {
        $tetelek += [pscustomobject]@{ Nev = 'beallitasok'; Ut = $beall; Tipus = 'adat' }
        Ok "Beállítások: $beall"
    } else { Warn "Nincs felhasználói beállítás mappa: $beall" }

    $adat = Join-Path $Profil 'abevjava'
    if ((Test-Path -LiteralPath $adat) -and -not (Test-Under $adat $prog) -and -not (Test-Under $prog $adat)) {
        $tetelek += [pscustomobject]@{ Nev = 'adatok'; Ut = $adat; Tipus = 'adat' }
        Ok "Adatok: $adat"
    }

    $figy = 0
    # Az elektronikus feladás (KR) mappája: az ÁNYK a KRDIR környezeti változóban is tárolja.
    $krDir = [Environment]::GetEnvironmentVariable('KRDIR', 'User')
    if (-not $krDir) { $krDir = [Environment]::GetEnvironmentVariable('KRDIR', 'Machine') }
    if ($krDir) { $krDir = $krDir.Trim().TrimEnd('\'); Ok "KR-mappa (KRDIR): $krDir" }

    # Egyéb adatmappák a beállításokból, plusz a kézzel megadottak.
    $kizart = @($env:windir, $env:TEMP, $env:ProgramData)
    $tag = @(Get-TagMappak)
    $jelolt = @(Get-EnykPaths @($beall, $prog)) + @($krDir) | ForEach-Object { [pscustomobject]@{ Ut = $_; Kezi = $false } }
    $jelolt = @($jelolt) + @($ExtraPath | ForEach-Object { [pscustomobject]@{ Ut = $_; Kezi = $true } })
    $n = 0
    foreach ($j in $jelolt) {
        $p = $j.Ut
        if (-not $p -or $p.Length -le 3) { continue }
        if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
        $p = (Resolve-Path -LiteralPath $p).Path.TrimEnd('\')
        if ($p -match '\\(java|jre|jdk)[^\\]*(\\|$)|Eclipse Adoptium|Zulu|BellSoft') { continue }
        if ($kizart | Where-Object { Test-Under $p $_ }) { continue }
        if ($tetelek | Where-Object { Test-Under $p $_.Ut }) { continue }
        if ($p -ieq $Profil -or (Test-Under $Profil $p)) { Warn "Túl tág mappa, kihagyom: $p"; $figy++; continue }
        if (-not $j.Kezi -and -not $NagyMappa) {
            $ok = $null
            if ($tag | Where-Object { $_ -ieq $p }) { $ok = 'személyes gyűjtőmappa (az ÁNYK-n kívül minden más is benne van)' }
            else {
                $mb = [math]::Round((Get-DirSize $p) / 1MB)
                if ($mb -gt $NagyMappaMB) { $ok = "$mb MB" }
            }
            if ($ok) {
                $kell = $false
                if (-not $Gui -and [Environment]::UserInteractive) {
                    $v = Read-Host "[FIGY] Nagy mappa a beállításokban: $p ($ok). Mentsem ezt is? (i/n)"
                    $kell = $v -match '^\s*i'
                }
                if (-not $kell) {
                    Warn "Kihagyom: $p ($ok). Ha kell, mentsd újra a nagy mappákkal együtt (-NagyMappa, vagy a felületen a jelölőnégyzettel)."
                    $figy++
                    continue
                }
            }
        }
        $n++
        $tetelek += [pscustomobject]@{ Nev = "extra$n"; Ut = $p; Tipus = 'adat' }
        Ok "Egyéb adatmappa: $p"
    }

    # Hely: a gyűjtés a TEMP-be megy, onnan a ZIP a célmappába.
    $osszes = ($tetelek | ForEach-Object { Get-DirSize $_.Ut } | Measure-Object -Sum).Sum
    Info "Mentendő adat: $([math]::Round($osszes / 1MB)) MB"
    New-Item -ItemType Directory -Force -Path $Cel | Out-Null
    foreach ($h in @($env:TEMP, (Resolve-Path $Cel).Path) | Select-Object -Unique) {
        $q = Split-Path -Qualifier $h -ErrorAction SilentlyContinue
        if (-not $q) { continue }
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$q'" -ErrorAction SilentlyContinue
        if ($d -and $d.FreeSpace -lt ($osszes * 1.1)) {
            Fail "Nincs elég hely a $q meghajtón: $([math]::Round($d.FreeSpace / 1MB)) MB szabad, kb. $([math]::Round($osszes * 1.1 / 1MB)) MB kell."
        }
    }

    $stage = Join-Path $env:TEMP "anyk-mentes-$Ido"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        foreach ($t in $tetelek) {
            Info "Másolás: $($t.Ut)"
            Copy-Dir $t.Ut (Join-Path $stage $t.Nev)
            $t | Add-Member -NotePropertyName Fajlok -NotePropertyValue (Get-FileCount (Join-Path $stage $t.Nev))
        }
        $man = [pscustomobject]@{
            Formatum    = 1
            Verzio      = $Verzio
            Datum       = (Get-Date).ToString('s')
            Gep         = $env:COMPUTERNAME
            Felhasznalo = $Felhasznalo
            Profil      = $Profil
            ProgramDir  = $prog
            KrDir       = $krDir
            Tetelek     = $tetelek
        }
        [IO.File]::WriteAllText((Join-Path $stage 'manifest.json'), ($man | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)

        New-Item -ItemType Directory -Force -Path $Cel | Out-Null
        $zip = Join-Path (Resolve-Path $Cel).Path "ANYK-mentes-$env:COMPUTERNAME-$Ido.zip"
        Info "Tömörítés: $zip"
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

        # Ellenőrzés: a ZIP-ben ugyanannyi fájl van, mint amennyit összegyűjtöttünk.
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        $zipDb = @($z.Entries | Where-Object { $_.Name }).Count
        $z.Dispose()
        $varDb = ($tetelek | Measure-Object Fajlok -Sum).Sum + 1
        if ($zipDb -ne $varDb) { Fail "A ZIP hiányos: $zipDb fájl a várt $varDb helyett." }
    } finally {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }

    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host ''
    if ($figy) { Warn "Kész, $figy figyelmeztetéssel. $zipDb fájl, $mb MB." } else { Ok "Kész. $zipDb fájl, $mb MB." }
    Ok "Mentés: $zip"
    if ($figy) { Vege 4 }
    Vege 0
}

# ======================================================================
# TELEPÍTÉS (Java + ÁNYK, ha hiányzik)
# ======================================================================
if ($Telepites) {
    $prog  = Find-AnykDir $ProgramDir
    $javaw = Find-Javaw $prog
    $celProg = if ($prog) { $prog } elseif ($ProgramDir) { $ProgramDir } else { $AnykAlapDir }
    if ((-not $javaw -or -not $prog) -and -not (Test-Admin)) { Invoke-Emelt @('-Telepites') }

    if ($javaw) { Ok "Java megvan: $javaw" }
    else {
        Warn 'Nincs Java a gépen.'
        $javaw = Install-Java
        if (-not $javaw) { Fail 'A Java telepítése nem sikerült. Telepíts kézzel (adoptium.net, Temurin JRE), aztán próbáld újra.' }
        Ok "Java telepítve: $javaw"
    }

    if ($prog) {
        Ok "ÁNYK megvan: $prog"
    } else {
        Warn 'Nincs ÁNYK a gépen.'
        try {
            Install-AnykNav $celProg
            $prog = $celProg
            Ok "ÁNYK telepítve: $prog"
            Set-AnykPathCfg $prog
            if (-not $NincsParancsikon) { New-Parancsikon $prog $javaw }
        } catch {
            Warn "A NAV-telepítő letöltése vagy kibontása nem sikerült: $($_.Exception.Message)"
            Warn 'Az ÁNYK a visszatöltéskor a mentésből települ.'
            Vege 3
        }
    }
    Repair-AddModules $prog $javaw
    Set-AbevJavaHome $prog $javaw
    Write-Host ''
    Ok 'A gép készen áll a visszatöltésre.'
    Vege 0
}

# ======================================================================
# VISSZATÖLTÉS
# ======================================================================
if (-not $Archiv) {
    $Archiv = Get-ChildItem -Path $PSScriptRoot -Filter 'ANYK-mentes-*.zip' -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Archiv) { Fail "Nem találok ANYK-mentes-*.zip fájlt a script mellett. Add meg: -Archiv <útvonal>" }
}
if (-not (Test-Path -LiteralPath $Archiv)) { Fail "Nincs ilyen fájl: $Archiv" }
$Archiv = (Resolve-Path -LiteralPath $Archiv).Path
if (-not $Telepito) {
    $t = Join-Path $PSScriptRoot 'abevjava_install.jar'
    if (Test-Path $t) { $Telepito = $t }
}

try { $man = Read-Manifest $Archiv } catch { Fail $_.Exception.Message }
Info "Mentés forrása: $($man.Gep) / $($man.Felhasznalo), készült: $($man.Datum)"

function Map-Ut([string]$p) {
    if (Test-Under $p $man.Profil) { return $Profil + $p.Substring($man.Profil.Length) }
    return $p
}

$prog  = Find-AnykDir $ProgramDir
$javaw = Find-Javaw $prog
$celProg = if ($prog) { $prog } elseif ($ProgramDir) { $ProgramDir } else { Map-Ut $man.ProgramDir }
$vedett = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:windir) | Where-Object { $_ }
$kellAdmin = (-not $javaw) -or [bool]($vedett | Where-Object { Test-Under $celProg $_ })

if ($kellAdmin -and -not (Test-Admin)) {
    $a = @('-Visszatoltes', '-Archiv', "`"$Archiv`"")
    if ($Telepito) { $a += '-Telepito', "`"$Telepito`"" }
    Invoke-Emelt $a
}

if (Test-AnykFut) { Fail 'Az ÁNYK most fut. Zárd be, aztán indítsd újra.' }

# --- 1. Java ---
if ($javaw) {
    Ok "Java megvan: $javaw"
} else {
    Warn 'Nincs Java a gépen.'
    $javaw = Install-Java
    if (-not $javaw) { Fail 'A Java telepítése nem sikerült. Telepítsd kézzel, aztán futtasd újra.' }
    Ok "Java telepítve: $javaw"
}

# --- 2. Kicsomagolás ---
$tmp = Join-Path $env:TEMP "anyk-vissza-$Ido"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Info 'Kicsomagolás...'
[IO.Compression.ZipFile]::ExtractToDirectory($Archiv, $tmp)
$progMentes = Join-Path $tmp 'program'

try {
    # --- 3. ÁNYK ---
    $mostTelepitett = $false
    if (-not $prog -and $Telepito) {
        Info "ÁNYK nincs telepítve. Hivatalos telepítő indul: $Telepito"
        Write-Host '      Kövesd a telepítő ablakát. A script megvárja a végét.'
        $java = Join-Path (Split-Path $javaw) 'java.exe'
        Start-Process -FilePath $java -ArgumentList '-jar', "`"$Telepito`"" -Wait
        $prog = Find-AnykDir $ProgramDir
        if (-not $prog) { Warn 'A telepítő után sem találom az ÁNYK-t. A mentett programmappát használom.' }
    }
    if ($prog) {
        Ok "ÁNYK telepítve: $prog"
        Info 'A mentett nyomtatványok pótlása (újabb fájlt nem írok felül)...'
        Copy-Dir $progMentes $prog @('/XO')
    } else {
        Info "ÁNYK nincs telepítve. Telepítés a mentésből ide: $celProg"
        Copy-Dir $progMentes $celProg
        $prog = $celProg
        $mostTelepitett = $true
        if (-not (Test-AnykDir $prog)) { Fail "A programmappa visszamásolása után sincs abevjava*.jar: $prog" }
        Ok "ÁNYK telepítve: $prog"
    }
    if ($mostTelepitett -and -not $NincsParancsikon) { New-Parancsikon $prog $javaw }
    Set-AnykPathCfg $prog

    # --- 4. Beállítások és adatok ---
    $hiba = 0
    $map = New-Object System.Collections.ArrayList
    [void]$map.Add(@($man.ProgramDir, $prog))
    $eredmeny = @()
    foreach ($t in $man.Tetelek | Where-Object { $_.Tipus -eq 'adat' }) {
        $cel = Map-Ut $t.Ut
        $meghajto = Split-Path -Qualifier $cel
        if (-not (Test-Path "$meghajto\")) {
            $uj = Join-Path $Profil "ANYK-$($t.Nev)"
            Warn "A $meghajto meghajtó nincs ezen a gépen. $($t.Ut) helyett ide kerül: $uj"
            $cel = $uj
        }
        if ($cel -ine $t.Ut) { [void]$map.Add(@($t.Ut, $cel)) }

        if ((Get-FileCount $cel) -gt 0) {
            $biz = "$cel.elotte-$Ido"
            Info "Már van tartalom itt: $cel. Biztonsági másolat: $biz"
            Copy-Dir $cel $biz
        }
        Info "Visszatöltés: $cel"
        Copy-Dir (Join-Path $tmp $t.Nev) $cel
        $eredmeny += [pscustomobject]@{ Ut = $cel; Vart = $t.Fajlok; Van = (Get-FileCount $cel) }
    }
    if ($man.Profil -ine $Profil) { [void]$map.Add(@($man.Profil, $Profil)) }

    # Az ÁNYK a beállítást <felhasználónév>.enyk néven keresi.
    $beall = Join-Path $Profil '.abevjava'
    $regiEnyk = Join-Path $beall "$($man.Felhasznalo).enyk"
    $ujEnyk = Join-Path $beall "$Felhasznalo.enyk"
    if ($man.Felhasznalo -ine $Felhasznalo -and (Test-Path $regiEnyk)) {
        if (Test-Path $ujEnyk) { Copy-Item $ujEnyk "$ujEnyk.elotte-$Ido" -Force }
        Copy-Item $regiEnyk $ujEnyk -Force
        Ok "Beállítás átnevezve az új felhasználóra: $ujEnyk"
    }

    # --- 5. Útvonalak átírása ---
    $map = @($map | Sort-Object { $_[0].Length } -Descending)
    $enyk = @()
    foreach ($d in @($beall, $prog)) {
        if (Test-Path -LiteralPath $d) {
            $enyk += Get-ChildItem -LiteralPath $d -Recurse -Filter '*.enyk' -File -ErrorAction SilentlyContinue |
                     Select-Object -ExpandProperty FullName
        }
    }
    $cfgUser = Join-Path $beall 'abevjavapath.cfg'
    if (Test-Path -LiteralPath $cfgUser) { $enyk += $cfgUser }
    if ($enyk) { Update-Enyk $enyk $map }
    $javaw = Find-Javaw $prog
    Repair-AddModules $prog $javaw
    Set-AbevJavaHome $prog $javaw

    # KRDIR környezeti változó annak a felhasználónak, akinek az adatai visszakerültek.
    if ($man.KrDir) {
        $ujKr = Convert-Utak $man.KrDir $map
        try {
            if ($Felhasznalo -ieq $env:USERNAME) {
                [Environment]::SetEnvironmentVariable('KRDIR', $ujKr, 'User')
            } else {
                $sid = (New-Object Security.Principal.NTAccount($Felhasznalo)).Translate([Security.Principal.SecurityIdentifier]).Value
                Set-ItemProperty -Path "Registry::HKEY_USERS\$sid\Environment" -Name KRDIR -Value $ujKr
            }
            Ok "KRDIR: $ujKr"
        } catch {
            Warn "A KRDIR változót nem tudtam beállítani. A(z) $Felhasznalo nevében futtasd: setx KRDIR `"$ujKr`""
            $hiba++
        }
    }

    # --- 6. Ellenőrzés ---
    Write-Host ''
    Info 'Ellenőrzés'
    if (Test-AnykDir $prog) { Ok "ÁNYK program: $prog" } else { Warn "Nincs abevjava*.jar: $prog"; $hiba++ }
    $java = Join-Path (Split-Path $javaw) 'java.exe'
    $ver = & cmd.exe /c "`"$java`" -version 2>&1" | Select-Object -First 1
    $global:LASTEXITCODE = 0
    if ($ver) { Ok "Java: $ver" } else { Warn 'A Java nem válaszol.'; $hiba++ }
    if (Test-Path $ujEnyk) { Ok "Beállítás: $ujEnyk" } else { Warn "Nincs felhasználói beállítás: $ujEnyk. Az ÁNYK első indításkor kéri."; }
    foreach ($e in $eredmeny) {
        if ($e.Van -ge $e.Vart) { Ok "$($e.Ut): $($e.Van) fájl" }
        else { Warn "$($e.Ut): csak $($e.Van) fájl a várt $($e.Vart) helyett"; $hiba++ }
    }
    Write-Host ''
    if ($hiba) { Warn "Kész, $hiba figyelmeztetéssel." } else { Ok 'Kész. Az ÁNYK indítható, a mentett nyomtatványok a helyükön vannak.' }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($hiba) { Vege 4 }
Vege 0
