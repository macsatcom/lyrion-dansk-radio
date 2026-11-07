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

## Forudsætning: PlayHLS v2

DR's kanaler streames som HLS (`.m3u8`), som Lyrion ikke kan afspille uden pluginnet **PlayHLS v2** (af bpa). Uden det spiller de kommercielle stationer fint, men DR-kanalerne starter ikke.

1. Hvis du har PlayHLS **v1** installeret, så afinstallér det først (v1 kræver ffmpeg og giver fejlen *"Couldn't create command line for hls playback"*).
2. Gå til **Indstillinger → Plugins → Yderligere arkiver** og tilføj:
   ```text
   http://bpa-code.github.io/bpaplugins/repo-playhls-v2.xml
   ```
3. Tryk **Anvend**, aktivér **PlayHLS**, og genstart Lyrion.

Mere info: [PlayHLS-tråden på Lyrion-forummet](https://forums.lyrion.org/forum/user-forums/3rd-party-software/99692-announce-playhls-plugin-plugin-to-play-apple-hls-m3u8-stream).

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

1. Download den nyeste `DKRadio-<version>.zip` under [Releases](https://github.com/macsatcom/lyrion-dansk-radio/releases).
2. Udpak indholdet til en mappe kaldet `DKRadio` i din Lyrion-servers `Plugins`-mappe.
3. Genstart Lyrion Music Server.

---

## Udvikling og test

Kør test-suiten lokalt:
```bash
prove -I. t/
```

Udgiv en ny version (hæv først `<version>` i `Plugins/DKRadio/install.xml`):
```bash
./build.sh --release   # tester, bygger zip, opretter GitHub-release plugin-v<version> og opdaterer repo.xml
git add repo.xml Plugins && git commit -m "release <version>" && git push
```
