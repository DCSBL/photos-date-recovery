# Plan: Phtofxr – foto-datums herstellen uit de bestandsnaam (iOS)

Status: **akkoord, in uitvoering**. Bundle-id `nl.dcsbl.phtofxr`. Persoonlijke app; de App Store is een doel voor later.

## 1. Doel

Phtofxr is een simpele, volledig lokale iPhone-app. Hij scant je fotobibliotheek en haalt uit de **originele bestandsnaam** een datum. Voorbeelden: `IMG_20170223_123456`, `IMG-20220201-WA0001`, `2015-05-18 20.17.49`. Die datum vergelijkt hij met de datum die Foto's nu toont, en per categorie stelt hij voor wat er moet gebeuren.

- Jij kiest per foto, of in bulk, "bewaar" of "niet".
- Pas na een duidelijke controle en jouw expliciete toestemming worden datums aangepast.
- Elke wijziging komt in een logboek en is terug te draaien.
- De datum waarop een foto is **toegevoegd**, blijft altijd staan.

De focus ligt op de iPhone, inclusief iPhone Duo. iPad doet mee zolang dat vanzelf meekomt.

Aanleiding: een import van zo'n 1000 oude foto's die nu allemaal op 11 en 12 oktober 2016 staan, in een bibliotheek van ongeveer 30.000 foto's.

## 2. Wat de Photos-API (PhotoKit) wel en niet kan

Onderzocht in de documentatie van iOS 27 (zie bronnen onderaan).

| Wat | API | Sinds | Lezen | Schrijven |
|---|---|---|---|---|
| Originele bestandsnaam (van de foto) | `PHAsset.extendedMetadata.originalFilename` (in bulk vooraf op te halen met `PHFetchOptions.prefetchAssetExtendedMetadata`) | iOS 27 | ja | nee |
| Bestandsnaam per bestand (JPEG/RAW/Live-video) | `PHAssetResource.filename` (vervangt `originalFilename`, die in iOS 27 verouderd is omdat hij onterecht nooit `nil` kon zijn) | iOS 27 (oud: iOS 9) | ja | nee |
| "Gemaakt"-datum, waarop Foto's sorteert | `PHAsset.creationDate` / `PHAssetChangeRequest.creationDate` | iOS 8 | ja | **ja** |
| "Toegevoegd"-datum (importmoment) | `PHAsset.addedDate` | iOS 26 | ja | **nee** (alleen lezen) |
| Bijschrift | `PHAssetExtendedMetadata.caption` / `PHAssetChangeRequest.caption` | iOS 27 | ja | ja |
| Laatst gewijzigd (welke wijziging dan ook) | `PHAsset.modificationDate` | iOS 8 | ja | nee |
| Tijdzone van de foto | niet beschikbaar | – | nee | nee |
| "Datum is handmatig aangepast" / originele datum vóór aanpassing | niet beschikbaar | – | nee | nee |
| Datum terugzetten naar origineel | geen API (`revertAssetContentToOriginal` gaat over bewerkingen, niet over datums) | – | – | – |

Wat dat betekent:

- **Bestandsnamen lezen kan.** Op de iPhone kan dat al sinds iOS 9. Op de Mac kwam die API pas in macOS 10.15. In de Foto's-app zelf toont de iPhone de naam pas sinds iOS 15. Met iOS 27 kan de app de namen van de hele bibliotheek in één keer vooraf ophalen.
  - Volgens Apple zijn de naam van de foto en de naam per bestand niet altijd gelijk. De app leest eerst de naam van de foto en valt anders terug op het hoofdbestand. De diagnose meet hoe vaak ze verschillen.
- **Alleen "Gemaakt" kun je aanpassen.** "Toegevoegd" is alleen-lezen. Daardoor kan de originele importdatum nooit verdwijnen, en kunnen we groeperen per import.
- **Per wijzigingsblok vraagt iOS toestemming.** Volgens Apple toont Foto's bij elke `performChanges` een melding. De app bundelt alles daarom in één blok, of een paar grote blokken.
- **Beperkte toegang.** De gebruiker kan de app toegang geven tot alleen gekozen foto's. Daarop werkt PhotoKit grotendeels hetzelfde, maar albums kan de app dan niet ophalen. Phtofxr ondersteunt dat volledig (zie §5).
- **Terugdraaien moet de app zelf regelen.** De Foto's-app heeft per foto "Herstel" onder *Pas datum en tijd aan*. Of dat ook werkt na een wijziging door een andere app, is niet gedocumenteerd en testen we op je toestel. De app houdt daarom een eigen logboek bij en draait daarmee terug.

## 3. Hoe de app beslist (categorieën)

Begrippen:

- **G** = huidige "Gemaakt"-datum
- **T** = "Toegevoegd"-datum
- **N** = datum uit de bestandsnaam
- **Δ** = |N − G|

Stappen per foto:

1. Door de app aangepast (volgens het logboek) → **Door app aangepast**
2. Eerder gekozen "niet bewaren" → **Overgeslagen**
3. Geen datum in de naam:
   - is G een reset-datum van een camera → **Verdacht**
   - anders → **Geen datum in naam**
4. Datum in de naam is onmogelijk (geen echte kalenderdag, in de toekomst, of vóór het minimumjaar 1995) → **Verdacht**
5. Datum maar geen tijd (zoals WhatsApp) → N = datum uit de naam + **tijd van G**
6. Δ < 24 uur → **Klopt al**. Hier vallen ook foto's in die je al met de hand hebt aangepast.
7. Formaat staat bekend als onbetrouwbaar → **Onzeker**
8. Δ tussen 1 en 7 dagen → **Onzeker**
9. Δ > 7 dagen:
   - G lijkt een "nooddatum" → **Zeker** (voorstel). G is een nooddatum als hij:
     - binnen een dag van T ligt, of
     - op een **stapeldag** valt: een dag met ≥ 50 foto's waarvan minstens de helft een naamdatum heeft die meer dan 7 dagen afwijkt, of
     - een reset-datum van een camera is: 1 januari vóór 06:00 in een jaar t/m 2012, of vóór het minimumjaar.
   - Anders heeft de foto een eigen datum die botst met de naam → **Onzeker** (conflict). Die tonen we wel, met de reden erbij.

**Zeker** en **Onzeker** vormen samen "Te beoordelen". In het selectiescherm staan ze per import, met binnen elke import een groep Zeker en een groep Onzeker. Zo selecteer je in één keer alle zekere foto's van een import.

Grenzen, minimumjaar en de drempels voor een stapeldag zijn instelbaar.

## 4. Bestandsnaam-formaten (eerste catalogus)

Elk formaat is een apart, aan/uit te zetten item in Instellingen, met een voorbeeld erbij. Voor elk formaat komen er positieve tests (moet herkend worden) en negatieve tests (mag niet herkend worden). De volgorde in de tabel is ook de volgorde waarin de app controleert: specifiek eerst, algemeen als laatste.

| id | Bron | Voorbeeld | Tijd | Zone | Standaard |
|---|---|---|---|---|---|
| `pixel` | Google Pixel | `PXL_20210101_123456789.jpg`, `PXL_20210101_123456789.MP.jpg` | ja | **UTC** | aan |
| `android-camera` | Android-camera en -video (o.a. Huawei, Xiaomi, OnePlus, Motorola, oude Samsung, Google) | `IMG_20170223_123456.jpg`, `IMG_20170223_123456_HDR.jpg`, `VID_20170223_123456.mp4`, `MVIMG_…`, `PANO_…` | ja | lokaal | aan |
| `onedrive` | OneDrive camera-upload | `20170223_123456000_iOS.jpg` | ja | UTC *(te verifiëren)* | aan, altijd **Onzeker** |
| `samsung` | Samsung Galaxy | `20170223_123456.jpg`, `20170223_123456(0).jpg` | ja | lokaal | aan |
| `whatsapp` | WhatsApp (Android) | `IMG-20220201-WA0001.jpg`, `VID-20220201-WA0001.mp4`, ook met `_` | **nee** | – | aan |
| `whatsapp-export` | WhatsApp desktop/web-export | `WhatsApp Image 2022-02-01 at 12.34.56.jpeg` | ja | lokaal | aan |
| `dropbox` | Dropbox camera-upload | `2015-05-18 20.17.49.jpg`, `2015-05-18 20.17.49-1.jpg` | ja | lokaal | aan |
| `android-screenshot` | Android-screenshot | `Screenshot_20170223-123456.png`, `Screenshot_2017-02-23-12-34-56.png` | ja | lokaal | aan |
| `macos-screenshot` | macOS-screenshot | `Screenshot 2023-02-23 at 12.34.56.png`, `Schermafbeelding 2023-02-23 om 12.34.56.png`, `Screen Shot 2017-02-23 at 12.34.56 PM.png` | ja | lokaal | aan |
| `signal` | Signal | `signal-2021-01-25-185030.jpg`, `signal-2023-05-12-12-34-56-789.jpg` | ja | lokaal | aan |
| `telegram` | Telegram Desktop | `photo_2022-02-01_12-34-56.jpg` | ja | lokaal | aan |
| `facebook` | Facebook | `FB_IMG_1486000000000.jpg` (Unix-tijd in ms) | ja | UTC | aan |
| `dji` | DJI-drone | `DJI_20230101123456_0001_D.JPG` | ja | lokaal | aan |
| `blackberry` | BlackBerry | `IMG-20120101-00001.jpg` | nee | – | aan |
| `windows-phone` | Windows Phone / Lumia | `WP_20140314_001.jpg`, `WP_20140314_12_34_56_Pro.jpg`, `wp_ss_20140314_0001.png` | soms | lokaal | aan |
| `skype` | Skype | `Skype_Picture_2017_02_23T12_34_56_123Z.jpeg` | ja | UTC | aan |
| `iso` | Algemeen ISO, ergens in de naam | `Vakantie 2017-02-23 12-34-56.jpg`, `20170223T123456.jpg`, `2017-02-23.jpg` | soms | lokaal | aan |
| `unix-timestamp` | Kaal Unix-tijdstempel | `1486000000.jpg`, `1486000000000.jpg` | ja | UTC | **uit**, en altijd Onzeker |
| `european-date` | Europees DD-MM-JJJJ | `Foto 23-02-2017.jpg` | nee | lokaal | **uit**, en altijd Onzeker |

Bevat bewust **geen** datum (tests moeten dit afvangen): `IMG_1234`, `IMG_E1234`, `DSC_0001`, `DSCN0001`, `DSCF0001`, `P1010001`, `GOPR0001`, `Snapchat-123456789`, `received_1234567890`, namen op basis van een UUID.

Randgevallen in de tests:

- schrikkeldag `20160229` (geldig) en `20170229` (ongeldig)
- `20170230` (ongeldig)
- zomertijdgat `2017-03-26 02:30` en dubbel uur `2017-10-29 02:30` in Europe/Amsterdam
- UTC-omrekening rond middernacht
- milliseconden
- 12-uursklok met AM/PM (ook met de smalle spatie van macOS)
- kleine letters, achtervoegsels als `(1)`, `-1`, `_HDR`, `.MP`
- jaar 1970 en jaren in de toekomst

## 5. Schermen (alleen standaardelementen, oranje tint)

`NavigationSplitView` met drie kolommen. Op de iPhone en een dichtgevouwen iPhone Duo klapt dat vanzelf in tot één stapel. Op een opengevouwen Duo (en iPad) staan de kolommen naast elkaar. De indeling volgt de vensterbreedte, niet het apparaat. Dit is hetzelfde patroon als in Rppl: alleen systeembalken en geen eigen zijbalk.

1. **Start** (zijbalk, vóór de scan):
   - **Toegang**: toestemming wordt pas gevraagd bij de eerste scan (just-in-time).
     - Bij beperkte toegang legt de app uit dat alleen de gekozen foto's worden gescand, met een knop "Selectie aanpassen".
     - Bij geweigerde toegang is er een knop naar Instellingen.
   - **Wat scannen**: foto's, video's en screenshots, elk aan/uit, plus "hele bibliotheek" of "gekozen albums". Albums kunnen alleen bij volledige toegang.
   - Knop "Scan bibliotheek", met voortgang.
2. **Resultaat** (zijbalk, na de scan): Te beoordelen (zeker · onzeker) · Verdacht · Klopt al · Geen datum in naam · Overgeslagen · Door app aangepast, elk met het aantal foto's.
3. **Lijst** (middenkolom): gegroepeerd per **Toegevoegd-dag** (importdag), grootste imports eerst. Bij Te beoordelen staan binnen elke import de groepen Zeker en Onzeker.
   - Per rij: miniatuur, bestandsnaam, nu → voorstel.
   - Bulk: alles in een groep selecteren, meervoudige selectie, en "Bewaar" / "Niet bewaren".
4. **Detail**: grote foto met huidige datum, voorstel, toegevoegd-datum, herkend formaat en de reden(en).
5. **Controleren en toepassen**:
   - Een apart scherm met het overzicht: aantal foto's, per import van → naar, en de keuze "Zet oorspronkelijke datum in bijschrift".
   - Daarna een expliciete bevestigingsknop, de systeemmelding van iOS, voortgang en een resultaat.
   - Er gebeurt niets zonder deze twee bevestigingen.
6. **Geschiedenis**: batches met datum en aantal, met "Draai batch terug" of terugdraaien per foto.
7. **Instellingen**: formaten aan/uit (met voorbeeld), drempels, minimumjaar, Diagnose.
8. **Diagnose**:
   - per foto alle naamvelden, de datums en de bijschriften
   - tellingen: hoe vaak een naam ontbreekt of verschilt
   - de duur van de scan

Toegankelijkheid:

- Dynamic Type tot en met de grootste maten
- VoiceOver-labels per rij
- geen informatie die alleen via kleur overkomt

Teksten zijn in het Engels met een Nederlandse vertaling (String Catalog).

## 6. Volledig lokaal: nul internet

- Geen netwerkcode en geen externe dependencies (geen SPM-pakketten, geen analytics, geen crashreporting).
- Een CI-check faalt als er toch iets van netwerkcode in de code komt: `URLSession`, `Network`, `WebKit`, `SafariServices`, URL's naar http(s), of pakketten van buiten.
- `isNetworkAccessAllowed = false` op alle verzoeken voor beelden en bestanden. Originele bestanden leest de app niet.
- Privacy-manifest: geen tracking en geen gegevensverzameling.
- Kanttekening: staat iCloud-foto's aan, dan synchroniseert **iOS zelf** de gewijzigde datums en bijschriften naar je andere apparaten. De app doet daar niets voor.

## 7. Opslag, bijschrift en terugdraaien

- **Logboek** (JSON Lines in Application Support, onderdeel van de gewone iPhone-backup):
  - per wijziging: `localIdentifier`, bestandsnaam, oude G, nieuwe G, T, oud bijschrift, formaat-id, batch-id en tijdstip
  - eerst een "voornemen"-regel, en na een geslaagde `performChanges` een "gedaan"-regel
  - bij de volgende start wordt een half afgemaakte batch gecontroleerd tegen Foto's
- **Bijschrift** (optie, staat aan):
  - De app voegt een regel toe, bijvoorbeeld `Phtofxr: oorspronkelijke datum 11-10-2016 14:23, toegevoegd 11-10-2016 14:23`.
  - Een bestaand bijschrift blijft staan; de regel komt eronder.
  - Bij terugdraaien haalt de app alleen die eigen regel weg.
- **Beslissingen** ("niet bewaren"): apart klein JSON-bestand, zodat ze een volgende scan overleven.
- **Terugdraaien**: `creationDate` krijgt de oude G uit het logboek en de eigen regel verdwijnt uit het bijschrift. T wordt nooit aangeraakt.

## 8. Testen en uitrollen

1. **Simulator**:
   - UI-tests met een nep-bibliotheek
   - een integratietest met echte foto's die CI in de simulator zet (`simctl addmedia`, met bestandsnamen zoals in jouw bibliotheek)
2. **Eigen toestel via Xcode**: zodra de simulator goed voelt. Het diagnosescherm controleert dan:
   - **A1** De bestandsnamen van je oude import komen door.
   - **A2** `addedDate` is de echte importdatum (11/12 oktober 2016?), ook op een iPhone die de foto's via iCloud kreeg.
   - **A3** Na een datumwijziging door de app toont Foto's het origineel en werkt "Herstel".
   - **A4** De toestemmingsmelding komt één keer per blok, ook bij 1.000 wijzigingen.
   - **A5** De tijd klopt met de verwachte lokale tijd.
   - **A6** De scan van 30.000 foto's is snel genoeg.
3. **TestFlight via Xcode Cloud**, zoals bij Rppl.

## 9. Repo-opbouw

```
Phtofxr.xcodeproj         Xcode-project met folder-synced groups
App/                      SwiftUI-app (dunne laag)
  PhotoLibrary/           LivePhotoLibrary (PhotoKit) + FakePhotoLibrary (UI-tests)
  Screens/
PhtofxrTests/             dunne app-tests + PhotoKit-integratietest
PhtofxrUITests/
PhtofxrCore/              Swift-package, alleen Foundation, draait ook op Linux
Config/                   Info.plist-aanvullingen
scripts/ci/               no-network-guard, simulator kiezen, foto's in de simulator zetten
.github/workflows/        core.yml, ios.yml, lint.yml, cancel-on-merge.yml
```

## 10. CI (snel houden)

| Workflow | Runner | Wat |
|---|---|---|
| `core.yml` | `ubuntu-24.04` + `swift`-container | `swift test` voor PhtofxrCore |
| `lint.yml` | `ubuntu-24.04` | no-network-guard |
| `ios.yml` → `build` | `xcode-27` (Xcode 27.2) | één keer `build-for-testing`, producten als artefact |
| `ios.yml` → `core-macos` | `xcode-27` | `swift test` op Apple-Foundation (dezelfde als op de iPhone) |
| `ios.yml` → `iphone` | `xcode-27` | app-tests + UI-tests op iPhone 17 |
| `ios.yml` → `duo` | `xcode-27` | UI-tests op de iPhone Duo-simulator |
| `ios.yml` → `integration` | `xcode-27` | echte foto's in de simulator + PhotoKit-test (nog niet verplicht) |

Snelheid:

- de testjobs draaien tegelijk op één build
- een nieuwe push annuleert de vorige run
- geen signing en geen index store
- UI-tests klein houden
- streefwaarde: hele run < 15 min

iPad krijgt pas een eigen job als iPad echt een doel wordt. CI draait op pull requests naar `main` en op elke push naar `main`.

## 11. Fases (elke fase = één PR)

1. **Skelet + Core + CI**: project, formatencatalogus, parser, classificatie met tests, workflows. De app scant alleen-lezend en toont categorieën, lijst, detail en diagnose.
2. **Beslissen + controleren + toepassen**: bulkselectie, controlescherm, toepassen in blokken, logboek, bijschrift.
3. **Geschiedenis + terugdraaien + instellingen** (formaten, drempels).
4. **Albums kiezen + beperkte toegang afmaken**.
5. **Op je toestel**: diagnose A1–A6, bijsturen, daarna TestFlight via Xcode Cloud.

## 12. Besluiten (uit de eerste ronde vragen)

- Conflicten (eigen datum versus naam) → Onzeker, wel tonen.
- Zeker en Onzeker per import gegroepeerd in het selectiescherm.
- Drempels < 24 u / 1–7 dagen / > 7 dagen, minimumjaar 1995.
- Tijdzone van de iPhone; formaten waarvan bekend is dat ze UTC gebruiken, worden omgerekend.
- Bij namen met alleen een datum blijft de tijd van G staan.
- Eerst markeren; uitvoeren pas na controle en expliciete toestemming.
- "Niet bewaren" wordt onthouden.
- Handmatig aangepaste foto's vallen in "Klopt al", plus een bakje "Door app aangepast".
- Optioneel bijschrift met de oorspronkelijke datum (in plaats van een trefwoord).
- De gebruiker kiest vóór de scan wat er meedoet; beperkte toegang wordt ondersteund.
- Eerst simulator, dan Xcode op je toestel, dan TestFlight via Xcode Cloud.
- Naam Phtofxr, `nl.dcsbl.phtofxr`, Engels + Nederlands, persoonlijke app.
- iPhone en iPhone Duo eerst; iPad zolang het vanzelf meekomt.

## Bronnen

- [PHAsset (addedDate, extendedMetadata, creationDate)](https://developer.apple.com/documentation/photos/phasset)
- [PHAsset.addedDate (iOS 26+)](https://developer.apple.com/documentation/photos/phasset/addeddate)
- [PHAssetExtendedMetadata (iOS 27+)](https://developer.apple.com/documentation/photos/phassetextendedmetadata)
- [PHAssetResource / filename (iOS 27+)](https://developer.apple.com/documentation/photos/phassetresource)
- [PHAssetChangeRequest / caption (iOS 27+)](https://developer.apple.com/documentation/photos/phassetchangerequest)
- [Forum: verschil tussen originalFilename op asset- en resource-niveau](https://developer.apple.com/forums/thread/843288)
- [PHFetchOptions (ondersteunde sorteer- en filtersleutels)](https://developer.apple.com/documentation/photos/phfetchoptions)
- [Requesting Changes to the Photo Library (één melding per change block)](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library)
- [Delivering an Enhanced Privacy Experience (beperkte toegang)](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)
- [Apple: datum terugzetten met "Herstel" op iPhone](https://support.apple.com/en-md/guide/iphone/iph0edb9c18f/ios)
- [GitHub: Xcode 27 runner-image](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/) en [image-release 20261104](https://github.com/actions/runner-images/releases/tag/xcode-27-arm64%2F20261104.0337)
- Rppl: `Docs/IPhoneDuo.md`, `RpplCore/.../WindowLayout.swift`, `.github/workflows/macos-ci.yml`, `core-tests.yml`, `cancel-on-merge.yml`
