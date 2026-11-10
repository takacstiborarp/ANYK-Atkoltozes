# ÁNYK átköltöztetés

Az ÁNYK (abevjava) programot, a letöltött nyomtatványokat, a beállításokat és a mentett adatokat viszi át egyik Windows gépről a másikra.

## Használat

1. Régi gép: zárd be az ÁNYK-t, és futtasd az `ANYK-Mentes.cmd` fájlt.
   A script mellé kerül egy `ANYK-mentes-<gépnév>-<dátum>.zip`.
2. Másold a mappát (scriptek + ZIP) pendrive-ra.
3. Új gép: futtasd az `ANYK-Visszatoltes.cmd` fájlt. Rendszergazdai jogot kér.

## Mit csinál a visszatöltés

- Java nincs: telepíti wingettel (`EclipseAdoptium.Temurin.21.JRE`).
- ÁNYK nincs: ha a script mellett van `abevjava_install.jar` (NAV-tól letöltve), a hivatalos telepítőt indítja.
  Ha nincs, a mentett programmappát másolja vissza, és parancsikont tesz az asztalra és a Start menübe.
- ÁNYK van: csak a hiányzó nyomtatványokat pótolja, újabb fájlt nem ír felül.
- Visszatölti a `%USERPROFILE%\.abevjava` (beállítások) és a `%USERPROFILE%\abevjava` (mentések, KR-fájlok) mappát.
  A beállításokban talált egyéb mappákat is (pl. `D:\ANYK_mentesek`).
- Ha a célmappában már van valami, előbb `<mappa>.elotte-<dátum>` néven biztonsági másolatot készít.
- Más felhasználónév vagy hiányzó meghajtó esetén átírja az útvonalakat az `.enyk` fájlokban (az eredetit `.elotte-<dátum>` néven megtartja).
- A végén ellenőriz: program, Java, fájlszámok.

## Kapcsolók

```
.\ANYK-Atkoltozes.ps1 -Mentes [-Cel E:\] [-ExtraPath 'D:\Valami'] [-ProgramDir 'C:\...\abevjava']
.\ANYK-Atkoltozes.ps1 -Visszatoltes [-Archiv <zip>] [-Telepito <abevjava_install.jar>] [-ProgramDir <cél>] [-NincsParancsikon]
```

A felhasználói adatok annak a felhasználónak a profiljába kerülnek, aki a scriptet indítja. Ezért annak a felhasználónak a nevében futtasd, aki az ÁNYK-t használni fogja.
