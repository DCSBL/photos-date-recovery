# AGENTS.md — Phtofxr

Instructions for AI coding agents working in this repo.

## Product north star

Phtofxr fixes photo dates from original filenames, **entirely on the device**. Trust beats features: the user
must be able to see why a date is proposed, decide in bulk, and undo anything.

## Hard constraints (do not "helpfully" break)

1. **No network.** No `URLSession`, `Network`, `WebKit`, `SafariServices`, web URLs in Swift sources, analytics,
   crash reporting or external packages. PhotoKit requests always set `isNetworkAccessAllowed = false`.
   `scripts/ci/no-network-guard.sh` enforces this in CI.
2. **No write without confirmation.** Scanning is read-only. A date only changes after the review screen and an
   explicit confirmation by the user.
3. **Journal before write.** Every change is written to the change journal before `performChanges`, so it can be
   undone and an interrupted batch can be reconciled.
4. **Only `creationDate` (and the opt-in caption line) change.** The added date is read-only and is never touched.
   Undo removes only the caption line Phtofxr added.
5. **OS floor:** iOS 27.2.
6. **Permissions just in time:** ask for photo access when the user starts a scan or diagnostics, never at launch.

## Architecture

| Layer | Owns | Avoids |
|---|---|---|
| `PhtofxrCore` | Filename formats, parser, classifier, grouping, settings, plain data types | PhotoKit, UIKit, SwiftUI |
| `App` | PhotoKit reading (`LivePhotoLibrary`), the fake library for UI tests, screens | Decisions that can be pure functions |

- Prefer pure logic in `PhtofxrCore` so `swift test` covers it on Linux.
- The app target uses main-actor default isolation. Data that background code creates (snapshots, reports)
  lives in Core; PhotoKit reading runs in `nonisolated static` functions inside `Task.detached`.
- Layout follows the window width, never the device or idiom (iPhone Duo folds and unfolds live).
- Standard SwiftUI elements only, one orange tint. Dynamic Type and VoiceOver labels are not optional.
- UI text: English base plus Dutch in `App/Localizable.xcstrings`.

## Filename formats

Add a format to `FilenameFormat.catalog` (order matters: specific before generic), with examples, and add
positive and negative cases to `FilenameDateParserTests`. Never rename a format `id`: settings store it.

## Testing

- GitHub runners are free for this repo: let CI run Xcode builds and simulators.
- `cd PhtofxrCore && swift test` is the source of truth for logic (Linux container in `core.yml`, macOS in `ios.yml`).
- `ios.yml` builds once on the `xcode-27` runner, then runs app tests and UI tests on iPhone 17 and iPhone Duo,
  plus the PhotoKit integration test with seeded simulator photos.
- UI tests use the fake library (`-phtofxrUITest`) and accessibility identifiers only.
- `PhtofxrScreenshotTests` takes Dutch screenshots of the main screens; CI publishes the latest set on the
  `screenshots` branch (replaced on every run). Name new screenshots `NN-name` so they sort in flow order.

## Cloud agents (Linux)

No Xcode or simulator: push and let CI build. If a Swift toolchain is present, run the Core tests.
`bash scripts/ci/no-network-guard.sh` runs anywhere.

## Source management

- Commit in small, concrete increments. PRs are squash-merged by a human.
- **PR title:** `<component>(<type>): <short description>`.
  - Components: `app`, `core`, `ci`, `docs`, `repo`.
  - Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- Use the PR template. Note which checks could not run where you worked.
