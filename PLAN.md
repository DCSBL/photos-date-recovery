# Plan: foto-datums herstellen uit de bestandsnaam (iOS)

Status: **concept, wacht op antwoorden** (zie "Open vragen" onderaan). Werknaam van de app: *Fotodatum* (nog niet definitief).

## 1. Doel in één alinea

Een simpele, volledig lokale iPhone/iPad-app die je hele fotobibliotheek scant, uit de **originele bestandsnaam** een datum haalt (bijvoorbeeld `IMG_20170223_123456`, `IMG-20220201-WA0001`, `2015-05-18 20.17.49`), die vergelijkt met de datum die Foto's nu toont, en per categorie voorstelt wat er moet gebeuren. Jij kiest per foto of in bulk "bewaar" of "niet". Pas daarna past de app in één keer de datums aan. Elke wijziging staat in een logboek en kun je terugdraaien. De datum waarop een foto is **toegevoegd** blijft altijd staan.

## 2. Wat de Photos-API (PhotoKit) wel en niet kan

Onderzocht in de documentatie van iOS 27 (zie bronnen onderaan).

| Wat | API | Sinds | Lezen | Schrijven |
|---|---|---|---|---|
| Originele bestandsnaam (van de foto) | `PHAsset.extendedMetadata.originalFilename` (in bulk vooraf op te halen met `PHFetchOptions.prefetchAssetExtendedMetadata`) | iOS 27 | ja | nee |
| Bestandsnaam per bestand (JPEG/RAW/Live-video) | `PHAssetResource.filename` (vervangt `originalFilename`, die in iOS 27 verouderd is omdat hij onterecht nooit `nil` kon zijn) | iOS 27 (oud: iOS 9) | ja | nee |
| "Gemaakt"-datum, waarop Foto's sorteert | `PHAsset.creationDate` / `PHAssetChangeRequest.creationDate` | iOS 8 | ja | **ja** |
| "Toegevoegd"-datum (importmoment) | `PHAsset.addedDate` | iOS 26 | ja | **nee** (alleen lezen) |
| Laatst gewijzigd (welke wijziging dan ook) | `PHAsset.modificationDate` | iOS 8 | ja | nee |
| Tijdzone van de foto | niet beschikbaar | – | nee | nee |
| "Datum is handmatig aangepast" / originele datum vóór aanpassing | niet beschikbaar | – | nee | nee |
| Datum terugzetten naar origineel | geen API (`revertAssetContentToOriginal` gaat over bewerkingen, niet over datums) | – | – | – |

Wat dat betekent:

- **Bestandsnamen lezen kan.** Op de iPhone kan dat al sinds iOS 9 via `PHAssetResource`. Op de Mac kwam die API pas in macOS 10.15. In de Foto's-app zelf toont de iPhone de bestandsnaam pas sinds iOS 15 in het infopaneel. Dat verklaart waarschijnlijk het verschil dat je je herinnert. Met iOS 27 is er een snellere route voor de hele bibliotheek: `extendedMetadata` kan per fetch in bulk vooraf worden opgehaald.
  - Let op: volgens Apple (DTS, forum) zijn de bestandsnaam van de foto en die van elk bestand niet altijd hetzelfde. Voor een losse JPEG uit een oude import horen ze gelijk te zijn. De app leest eerst de naam van de foto en valt anders terug op de naam van het hoofdbestand. De diagnose (fase 0) controleert dit.
- **Alleen "Gemaakt" kun je aanpassen.** "Toegevoegd" is alleen-lezen. Daardoor kan de originele importdatum nooit verdwijnen, en kunnen we groeperen per import.
- **Per wijzigingsblok vraagt iOS toestemming.** Volgens Apple toont Foto's bij elke `performChanges`-aanroep een melding. Daarom: eerst alles markeren, dan **één** knop "Toepassen", met alle wijzigingen in één blok of een paar grote blokken.
- **Terugdraaien moet de app zelf regelen.** De Foto's-app heeft per foto "Herstel" onder *Pas datum en tijd aan*. Of dat ook werkt na een wijziging door een andere app, staat nergens gedocumenteerd. Dat testen we op je toestel. De app houdt daarom een eigen logboek bij (oude en nieuwe datum per foto) en draait daarmee per batch of per foto terug.

## 3. Hoe de app beslist (categorieën)

Begrippen:

- **G** = huidige "Gemaakt"-datum
- **T** = "Toegevoegd"-datum
- **N** = datum uit de bestandsnaam
- **Δ** = |N − G|

Stappen per foto:

1. Geen datum in de naam → **Geen datum in naam**
2. Datum in de naam is onmogelijk (geen echte kalenderdag, in de toekomst, of vóór het minimumjaar, standaard 1995) → **Verdacht**
3. Datum maar geen tijd (zoals WhatsApp) → N = datum uit de naam + **tijd van G** (jouw regel: de tijd blijft origineel)
4. Δ < 24 uur → **Klopt al**. Hier vallen ook foto's in die je al met de hand hebt aangepast.
5. Δ tussen 1 en 7 dagen → **Onzeker**
6. Δ > 7 dagen:
   - G lijkt een "nooddatum" → **Voorstel**. G is een nooddatum als hij:
     - binnen een dag van T ligt (bij de import kreeg de foto de importdatum), of
     - op een **stapeldag** valt: een dag met heel veel foto's (standaard ≥ 50) waarvan het grootste deel een naamdatum heeft die ver weg ligt, of
     - een typische reset-datum van een camera is (1 januari 00:00 in 1970, 1980, 1990, 2000, 2001, 2004, … of vóór het minimumjaar).
   - Anders: G is een "echte" eigen datum die botst met de naam → **Onzeker** (conflict)
7. Eerder gekozen "niet bewaren" → **Overgeslagen** (komt niet terug als voorstel)
8. Al door de app aangepast (volgens het logboek) → **Door app aangepast**

Grenzen, minimumjaar en de drempel voor een stapeldag zijn instelbaar.

## 4. Bestandsnaam-formaten (eerste catalogus)

Elk formaat is een apart, aan/uit te zetten item in Instellingen, met een voorbeeld erbij. Voor elk formaat komen er positieve tests (moet herkend worden) en negatieve tests (mag niet herkend worden).

| # | Bron | Voorbeeld | Tijd | Zone | Standaard |
|---|---|---|---|---|---|
| 1 | Android-camera (o.a. Huawei, Xiaomi, OnePlus, Motorola, oude Samsung) | `IMG_20170223_123456.jpg`, `IMG_20170223_123456_HDR.jpg`, `IMG_20170223_123456789.jpg` | ja | lokaal | aan |
| 2 | Android-video | `VID_20170223_123456.mp4` | ja | lokaal | aan |
| 3 | Google Pixel | `PXL_20210101_123456789.jpg`, `PXL_20210101_123456789.MP.jpg` | ja | **UTC** | aan |
| 4 | Google (motion/panorama) | `MVIMG_20190101_123456.jpg`, `PANO_20170223_123456.jpg` | ja | lokaal | aan |
| 5 | Samsung Galaxy | `20170223_123456.jpg`, `20170223_123456(0).jpg` | ja | lokaal | aan |
| 6 | WhatsApp (Android) | `IMG-20220201-WA0001.jpg`, `VID-20220201-WA0001.mp4`, ook met `_` | **nee** | – | aan |
| 7 | WhatsApp desktop/web-export | `WhatsApp Image 2022-02-01 at 12.34.56.jpeg` | ja | lokaal | aan |
| 8 | Dropbox camera-upload | `2015-05-18 20.17.49.jpg`, `2015-05-18 20.17.49-1.jpg` | ja | lokaal | aan |
| 9 | Android-screenshot | `Screenshot_20170223-123456.png`, `Screenshot_2017-02-23-12-34-56.png`, `Screenshot_20170223-123456_WhatsApp.jpg` | ja | lokaal | aan |
| 10 | macOS-screenshot | `Screenshot 2023-02-23 at 12.34.56.png`, `Schermafbeelding 2023-02-23 om 12.34.56.png`, `Screen Shot 2017-02-23 at 12.34.56 PM.png` | ja | lokaal | aan |
| 11 | Signal | `signal-2021-01-25-185030.jpg`, `signal-2023-05-12-12-34-56-789.jpg` | ja | lokaal | aan |
| 12 | Telegram Desktop | `photo_2022-02-01_12-34-56.jpg` | ja | lokaal | aan |
| 13 | Facebook | `FB_IMG_1486000000000.jpg` (Unix-tijd in ms) | ja | UTC | aan |
| 14 | DJI-drone | `DJI_20230101123456_0001_D.JPG` | ja | lokaal | aan |
| 15 | BlackBerry | `IMG-20120101-00001.jpg` | nee | – | aan |
| 16 | Windows Phone / Lumia | `WP_20140314_001.jpg`, `WP_20140314_12_34_56_Pro.jpg` | soms | lokaal | aan |
| 17 | Skype | `Skype_Picture_2017_02_23T12_34_56_123Z.jpeg` | ja | UTC | aan |
| 18 | OneDrive camera-upload | `20170223_123456000_iOS.jpg` | ja | UTC? *(te verifiëren)* | aan → Onzeker |
| 19 | Algemeen ISO | `2017-02-23_12-34-56.jpg`, `20170223T123456.jpg`, `2017-02-23.jpg` | soms | lokaal | aan |
| 20 | Kaal Unix-tijdstempel | `1486000000.jpg`, `1486000000000.jpg` | ja | UTC | **uit** (botst met bijv. Snapchat-nummers) |
| 21 | Europees DD-MM-JJJJ | `Foto 23-02-2017.jpg` | soms | lokaal | **uit**, en alleen als het eenduidig is (dag > 12) |

Bevat bewust **geen** datum (tests moeten dit afvangen): `IMG_1234`, `IMG_E1234`, `DSC_0001`, `DSCN0001`, `DSCF0001`, `P1010001`, `GOPR0001`, `Snapchat-123456789`, `received_1234567890`, namen op basis van een UUID.

Achtervoegsels die we negeren: `(1)`, `-1`, `_1`, ` copy`, `-edited`, `_HDR`, `.MP`, hoofd- of kleine letters in de extensie, `.HEIC`/`.JPG`/`.PNG`/`.MOV`/`.MP4`.

Randgevallen in de tests:

- schrikkeldag `20160229` (geldig) en `20170229` (ongeldig)
- `20170230` (ongeldig)
- zomertijdgat `2017-03-26 02:30` in Europe/Amsterdam
- dubbel uur `2017-10-29 02:30`
- UTC-omrekening rond middernacht
- milliseconden
- jaar 1970 en jaren in de toekomst

## 5. Schermen (alleen standaardelementen, één kleurtint)

`NavigationSplitView` met drie kolommen. Op de iPhone en een dichtgevouwen iPhone Duo klapt dat vanzelf in tot één stapel. Op iPad en een opengevouwen Duo staan de kolommen naast elkaar. De indeling volgt de vensterbreedte, niet het apparaat. Dit is hetzelfde patroon als `WindowLayout` en de split-navigatie in Rppl: alleen systeembalken, geen eigen zijbalk, en de systeemdeler komt op de vouw.

1. **Start / Scan**: uitleg in één zin, knop "Scan bibliotheek" en voortgang. Toestemming vraagt de app pas hier (just-in-time). Bij "Beperkte toegang" legt de app uit waarom volledige toegang nodig is.
2. **Categorieën** (zijbalk): Voorstel · Onzeker · Verdacht · Klopt al · Geen datum in naam · Overgeslagen · Door app aangepast, elk met het aantal foto's.
3. **Lijst** (middenkolom): gegroepeerd per **Toegevoegd-dag** (importdag), grootste imports eerst (sorteerbaar). Per rij: miniatuur, bestandsnaam, nu → voorstel, verschil.
   - Bulk: "Selecteer alles in deze import", meervoudige selectie, en "Bewaar" / "Niet bewaren" voor de selectie, de hele groep of de hele categorie.
   - Vegen per rij voor snelle keuzes.
4. **Detail**: grote foto met huidige datum, voorstel, toegevoegd-datum, herkend formaat en een "Waarom"-regel (bijvoorbeeld "stapeldag 12-03-2018, 1043 foto's").
5. **Toepassen**: samenvatting ("1.234 foto's krijgen een nieuwe datum"), daarna één systeemmelding van iOS, voortgang, klaar.
6. **Geschiedenis**: batches met datum en aantal, met "Draai batch terug" of terugdraaien per foto.
7. **Instellingen**: formaten aan/uit (met voorbeeld), drempels, minimumjaar, tijdzone, en welke media meedoen.
8. **Diagnose** (alleen fase 0 en debug): controleert de aannames uit §8 op je echte bibliotheek.

Toegankelijkheid:

- Dynamic Type tot en met de grootste maten
- VoiceOver-labels per rij, bijvoorbeeld "IMG_20170223_123456, nu 12 maart 2018, voorstel 23 februari 2017"
- geen informatie die alleen via kleur overkomt

## 6. Volledig lokaal: nul internet

- Geen netwerkcode en geen externe dependencies (geen SPM-pakketten, geen analytics, geen crashreporting).
- Een CI-check faalt als er toch iets van netwerkcode in de code komt: `URLSession`, `import Network`, `WebKit`, `SafariServices`, `Link(destination:` met http(s), of een `Package.resolved` met dependencies.
- `isNetworkAccessAllowed = false` op alle verzoeken voor beelden en bestanden. Miniaturen komen dus alleen van wat al lokaal staat. Originele bestanden leest de app niet.
- Privacy-manifest: geen tracking en geen gegevensverzameling. De enige API waarvoor Apple een reden vraagt, is UserDefaults.
- Kanttekening: staat iCloud-foto's aan, dan synchroniseert **iOS zelf** de gewijzigde datums naar je andere apparaten, ook bij terugdraaien. De app doet daar niets voor.

## 7. Opslag en terugdraaien

- **Logboek** (JSON Lines in Application Support, onderdeel van de gewone iPhone-backup):
  - per wijziging: `localIdentifier`, bestandsnaam, oude G, nieuwe G, T, formaat-id, batch-id en tijdstip
  - eerst een "voornemen"-regel, en na een geslaagde `performChanges` een "gedaan"-regel
  - bij de volgende start wordt een half afgemaakte batch gecontroleerd tegen de echte datum in Foto's
- **Beslissingen** ("niet bewaren"): apart klein JSON-bestand, zodat ze een volgende scan overleven.
- **Terugdraaien** = dezelfde route terug: `creationDate` krijgt de oude G uit het logboek. T wordt nooit aangeraakt.

## 8. Fase 0: aannames verifiëren op jouw iPhone

Dit kan niet in de simulator of CI. Het diagnosescherm controleert:

- **A1** `extendedMetadata.originalFilename` geeft de oude bestandsnamen van de import, en die zijn gelijk aan `PHAssetResource.filename`.
- **A2** `addedDate` van de oude import is de echte importdatum, ook op een iPhone die de foto's via iCloud binnenkreeg.
- **A3** Na een datumwijziging door de app toont Foto's de originele datum en werkt "Herstel".
- **A4** De toestemmingsmelding komt één keer per blok, ook bij 1.000+ wijzigingen in één blok.
- **A5** De getoonde tijd na de wijziging klopt met de verwachte lokale tijd (tijdzone).
- **A6** Hoe snel een scan van je volledige bibliotheek is.

## 9. Repo-opbouw

```
Fotodatum.xcodeproj            Xcode-project met folder-synced groups: nieuwe bestanden zonder projectgedoe
App/                           SwiftUI, dunne laag
  PhotoLibrary/                LivePhotoLibrary (PhotoKit) + FakePhotoLibrary (UI-tests, via launch-argument)
  Screens/
AppTests/                      dunne app-tests + PhotoKit-integratietest (simulator met echte foto's)
AppUITests/
DateRecoveryCore/              Swift-package, alleen Foundation, draait ook op Linux
  Sources/                     FilenameDateParser, FormatCatalog, Classifier, ImportGrouping, Journal, Settings
  Tests/                       Swift Testing + Fixtures/filenames.json (honderden voorbeeldnamen)
scripts/ci/                    no-network-guard.sh, seed-simulator-photos.sh, pick-simulator.py
.github/workflows/             core.yml, ios.yml, lint.yml, cancel-on-merge.yml
AGENTS.md                      afspraken voor agents (in de stijl van Rppl)
```

Overgenomen uit Rppl:

- pure logica in een Core-package dat `swift test` op Linux dekt
- de UI volgt de vensterbreedte, niet het apparaat
- in CI één keer bouwen en daarna meerdere testjobs
- Linux-tests in de `swift`-container
- lopende runs annuleren bij merge
- een problem matcher die Xcode-waarschuwingen als annotaties in de PR zet

## 10. CI (snel houden)

| Workflow | Runner | Wat | Doel |
|---|---|---|---|
| `core.yml` | `ubuntu-24.04` + `swift`-container | `swift test` voor DateRecoveryCore, met `.build` gecachet | ≤ 3 min |
| `lint.yml` | `ubuntu-24.04` | no-network-guard, SwiftLint, yamllint | ≤ 1 min |
| `ios.yml` → `build` | `xcode-27` (Xcode 27.2) | één keer `build-for-testing`, producten als artefact | ≈ 5 min |
| `ios.yml` → `iphone` | `xcode-27` | app-tests + UI-smoke op iPhone 17 + integratietest (`simctl addmedia` met ±20 JPEG's zonder EXIF met gemaakte namen, plus `simctl privacy grant`) | parallel |
| `ios.yml` → `duo` | `xcode-27` | UI-smoke op de **iPhone Duo**-simulator (gevouwen en open) | parallel |
| `ios.yml` → `ipad` | `xcode-27` | UI-smoke op iPad Pro 13" (liggend split, staand) | parallel |

Volgens de release-notes van de image heeft de `xcode-27`-runner van GitHub Xcode 27.2 met simulators voor iOS 27.2, waaronder **iPhone Duo** en iPads. De oudere `macos-26`-image heeft geen Xcode 27.

Snelheid:

- een docs-only PR slaat de macOS-jobs over, maar ze rapporteren wel een status
- een nieuwe push annuleert de vorige run (`concurrency`)
- `ONLY_ACTIVE_ARCH`, geen index store, geen signing
- UI-tests klein houden: 5 tot 8 scenario's met de nep-bibliotheek
- streefwaarde: hele PR-run < 15 min wall-clock

## 11. Fases (elke fase = één PR)

1. **Skelet + CI + Diagnose**: project, Core-package, workflows, diagnosescherm. Daarna voer jij A1–A6 uit op je iPhone.
2. **Herkenning van bestandsnamen**: formatencatalogus, parser en fixtures met tests (alleen Core).
3. **Scan + categorieën**: alleen lezen. PhotoKit-route, classificatie, groepering per import, lijst en detail.
4. **Beslissen + toepassen**: bulkselectie, toepassen in blokken, logboek.
5. **Geschiedenis + terugdraaien + instellingen**.
6. **Afwerking**: iPad/Duo, toegankelijkheid, volledige UI- en integratietests, privacy-manifest.

## 12. Open vragen

Zie het chatbericht. Antwoorden worden hier verwerkt.

## Bronnen

- [PHAsset (addedDate, extendedMetadata, creationDate)](https://developer.apple.com/documentation/photos/phasset)
- [PHAsset.addedDate (iOS 26+)](https://developer.apple.com/documentation/photos/phasset/addeddate)
- [PHAssetExtendedMetadata (iOS 27+)](https://developer.apple.com/documentation/photos/phassetextendedmetadata)
- [PHAssetResource / filename (iOS 27+)](https://developer.apple.com/documentation/photos/phassetresource)
- [Forum: verschil tussen originalFilename op asset- en resource-niveau](https://developer.apple.com/forums/thread/843288)
- [PHAssetChangeRequest](https://developer.apple.com/documentation/photos/phassetchangerequest)
- [PHFetchOptions (ondersteunde sorteer- en filtersleutels)](https://developer.apple.com/documentation/photos/phfetchoptions)
- [Requesting Changes to the Photo Library (één melding per change block)](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library)
- [Apple: datum terugzetten met "Herstel" op iPhone](https://support.apple.com/en-md/guide/iphone/iph0edb9c18f/ios)
- [GitHub: Xcode 27 runner-image](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/) en [image-release 20261104](https://github.com/actions/runner-images/releases/tag/xcode-27-arm64%2F20261104.0337)
- Rppl: `Docs/IPhoneDuo.md`, `RpplCore/.../WindowLayout.swift`, `.github/workflows/macos-ci.yml`, `core-tests.yml`, `cancel-on-merge.yml`
