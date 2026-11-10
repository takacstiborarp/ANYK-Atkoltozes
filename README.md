# ÁNYK átköltöztetés

Készítette: Takács Tibor - ARP Hungary Kft. +36 30 526-9886, takacstibor@arphungary.hu

Az ÁNYK (abevjava) programot, a letöltött nyomtatványokat, a beállításokat és a mentett adatokat viszi át egyik Windows gépről a másikra.

## MSI (ajánlott)

`dist\ANYK-Atkoltozes-<verzió>.msi` telepítése után a program elindul (Start menü és asztal: "ÁNYK átköltöztetés"). Indításkor megkérdezi, mit szeretnél:

- **Mentés** (régi gép): bekéri, hol van az ÁNYK programmappája (abevjava, automatikusan kitöltve, ha megtalálja), és hova kerüljön a ZIP.
- **Visszatöltés** (új gép, rendszergazdai jogot kér):
  1. ellenőrzi a Javát és az ÁNYK-t, ami hiányzik, telepíti,
  2. bekéri a mentést (ZIP), és a helyére teszi.

Az MSI magától nem tud fájlválasztót mutatni (ez a Windows Installer korlátja), ezért egy kis grafikus programot telepít, és azt indítja el a telepítés végén.

## Parancssor

1. Régi gép: zárd be az ÁNYK-t, futtasd az `ANYK-Mentes.cmd`-t. A script mellé kerül egy `ANYK-mentes-<gépnév>-<dátum>.zip`.
2. Másold a mappát (scriptek + ZIP) pendrive-ra.
3. Új gép: futtasd az `ANYK-Visszatoltes.cmd`-t. Rendszergazdai jogot kér.

```
.\ANYK-Atkoltozes.ps1 -Mentes [-Cel E:\] [-ExtraPath 'D:\Valami'] [-ProgramDir 'C:\...\abevjava']
.\ANYK-Atkoltozes.ps1 -Telepites [-ProgramDir <cél>]
.\ANYK-Atkoltozes.ps1 -Visszatoltes [-Archiv <zip>] [-Telepito <abevjava_install.jar>] [-ProgramDir <cél>] [-NincsParancsikon]
```

Kilépési kódok: 0 rendben, 1 hiba, 3 az ÁNYK nem települt a NAV-ról (a visszatöltés a mentésből telepíti), 4 kész, de figyelmeztetéssel.

## Mit ment

- az ÁNYK programmappáját a letöltött nyomtatványokkal (enélkül a régi mentések nem nyílnak meg),
- `%USERPROFILE%\.abevjava` (beállítások, `<felhasználó>.enyk`),
- `%USERPROFILE%\abevjava` (mentések, KR-fájlok, napló),
- a beállításokban hivatkozott egyéb mappákat (pl. `D:\ANYK_mentesek`).

## Mit csinál a visszatöltés

- **Java nincs:** Eclipse Temurin 21 JRE wingettel, ha nincs winget, az adoptium.net MSI-jével.
- **ÁNYK nincs:** letölti a hivatalos telepítőt a nav.gov.hu-ról, és úgy bontja ki, ahogy a NAV telepítője: `Program Files\abevjava`, `abevjava_start.bat`, `setenv.bat`, `%windir%\abevjavapath.cfg`, parancsikon. Ha a NAV nem érhető el, a mentett programmappát másolja vissza.
- **ÁNYK van:** csak a hiányzó nyomtatványokat pótolja, újabb fájlt nem ír felül.
- **Felhasználói adatok:** visszatölti őket. Ha a célmappában már van valami, előbb `<mappa>.elotte-<dátum>` másolatot készít.
- **Más felhasználónév:** a `<régi>.enyk` fájlt átmásolja `<új>.enyk` néven. Az útvonalakat átírja az `.enyk` fájlokban, az eredetit megtartja.
- **Java-kapcsoló:** a NAV indítószkriptje `--add-modules=java.se.ee` kapcsolóval indul. Ha a gépen lévő Java ezt nem fogadja el, a script kiveszi a kapcsolót, különben az ÁNYK nem indulna.
- **A végén ellenőriz:** program, Java, beállítás, fájlszámok.

A felhasználói adatok annak a felhasználónak a profiljába kerülnek, aki a programot elindítja (az emelt jogú újraindítás is ezt a profilt használja).

## MSI építése

Kell: WiX v5 (`dotnet tool install --global wix`) és `wix extension add -g WixToolset.UI.wixext`.

```
powershell -ExecutionPolicy Bypass -File .\build-msi.ps1
```

A verzió az `ANYK-Atkoltozes.ps1` `$Verzio` sorából jön. Minden változtatásnál emeld. Az ikont, a telepítő képeit (`dialog.bmp`, `banner.bmp`), a kis logót és a leírást a build generálja az `installer\arp_logo.png`-ből.

## Arculat

ARP Hungary: teal logó, paletta `#156366` (fő szín), `#0A4343`, `#5C6B73` (szöveg), `#C9D3D7` (vonal), `#F2F7F7` (háttér), figyelmeztetés `#A8681B`, hiba `#8A2B2B`. Szögletes elemek, egyenes vonalak. A "Készítette" sor a felület láblécében, a telepítő leírásában és befejező lapján, valamint a Programok és szolgáltatások adatai között is szerepel.

## Licenc

MIT, lásd a [LICENSE](LICENSE) fájlt. A kód szabadon használható, módosítható és továbbadható, a szerzői jogi megjegyzés megtartásával. Garancia nélkül.

Az ARP Hungary logó és név nem része a licencnek, azok az ARP Hungary Kft. tulajdonában maradnak. A program által letöltött ÁNYK (NAV) és Java (Eclipse Temurin) a saját licencfeltételeik szerint használható.
