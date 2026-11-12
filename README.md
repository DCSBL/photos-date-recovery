# Phtofxr

A small iPhone app that fixes photo dates from their original filenames, entirely on the device.

Old imports often end up with the date of the import instead of the date the photo was taken: a thousand
photos on one day. Their filenames usually still say when they were taken (`IMG_20170223_123456.jpg`,
`IMG-20220201-WA0001.jpg`, `2015-05-18 20.17.49.jpg`). Phtofxr reads those names through PhotoKit, compares
them with the date in Photos, and sorts every photo into a category: certain, uncertain, suspicious, already
correct or no date in the name. Nothing changes until you have reviewed the proposals and confirmed.

- iOS 27.2 or later, iPhone first (including iPhone Duo); iPad works where it comes for free.
- No network access, no external dependencies, no analytics.
- The date a photo was *added* to the library is read-only in PhotoKit, so the original import date always survives.

See [PLAN.md](PLAN.md) for the plan, the PhotoKit research and the decisions so far.

## Layout

| Path | What |
|---|---|
| `PhtofxrCore/` | Swift package with the pure logic: filename formats, parser, classifier, grouping. Runs on Linux. |
| `App/` | SwiftUI app: PhotoKit reading, screens. |
| `PhtofxrTests/`, `PhtofxrUITests/` | App tests, PhotoKit integration test, UI tests. |
| `scripts/ci/` | CI helpers: simulator picking, seeding photos into a simulator, the no-network guard. |

## Checks

- `cd PhtofxrCore && swift test` — core logic (Linux or macOS).
- GitHub Actions run the core tests on Linux and macOS, build the app once on the `xcode-27` runner and run
  the app, UI and PhotoKit integration tests on iPhone 17 and iPhone Duo simulators.
- Screenshots of the latest run (Dutch, fake library) are on the
  [`screenshots` branch](https://github.com/DCSBL/photos-date-recovery/tree/screenshots).
