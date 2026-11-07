# Lyrion Dansk Radio (DK Radio Plugin)

Lyrion Music Server (LMS / Squeezebox) plugin, der giver adgang til alle over 230 danske radiostationer fra radio.dk.

## Funktioner

- **Alle stationer**: Komplet alfabetisk liste sorteret efter dansk retskrivning (Æ, Ø, Å til sidst).
- **Regioner**: Opdelt i de 5 danske regioner (*Hovedstaden, Sjælland, Syddanmark, Midtjylland, Nordjylland*) samt *Øvrige*.
- **Genrer**: Gennemse efter genrer (Pop, Nyheder, Rock, Jazz osv.).
- **DR**: Dedikeret mappe med alle DR's landsdækkende og regionale kanaler (P1–P8, regional P4/P5 osv.).
- **Automatisk stream-optimering**: Vælger automatisk den bedste tilgængelige stream (AAC prioriteret over MP3, og højeste bitrate).
- **Resilient**: Cacher stationer lokalt i 24 timer og falder automatisk tilbage på senest kendte liste, hvis radio.dk's API er midlertidigt utilgængeligt.

---

## Installation i Lyrion (LMS)

Du kan installere pluginnet direkte via Lyrions webinterface ved at tilføje dette GitHub-arkiv:

1. Åbn Lyrion webinterface (**Indstillinger** / **Settings**).
2. Vælg fanen **Plugins**.
3. Rul ned i bunden til **Yderligere arkiver** (Additional Repositories).
4. Indsæt denne URL:
   ```text
   https://raw.githubusercontent.com/macsatcom/lyrion-dansk-radio/main/repo.xml
   ```
5. Tryk på **Anvend** (Apply).
6. Find **DK Radio** på plugin-listen under *Radio*, sæt flueben ved det, og tryk **Anvend**.
7. Genstart Lyrion-serveren, når den beder om det.

Efter genstart finder du **DK Radio** under din musikafspillers **Radio**-menu.

---

## Manuel installation

Hvis du foretrækker manuel installation:

1. Download [`DKRadio-0.1.0.zip`](DKRadio-0.1.0.zip).
2. Udpak indholdet til en mappe kaldet `DKRadio` i din Lyrion-servers `Plugins`-mappe.
3. Genstart Lyrion Music Server.

---

## Udvikling og test

Kør test-suiten lokalt:
```bash
prove -I. t/
```

Byg ny zip og `repo.xml`:
```bash
BASE_URL=https://raw.githubusercontent.com/macsatcom/lyrion-dansk-radio/main ./build.sh
cp dist/* .
```
