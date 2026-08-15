# Accord Manual — Implementation Plan

**Goal:** Build a fully offline, native iOS/iPadOS technical manual for Honda Accord CL/CM (2003–2008) and a macOS Swift command-line importer that turns the archived site into a versioned, immutable data package.

**Architecture:** `Importer` is a Swift Package with no external dependencies. It parses the source catalogue when present, otherwise discovers local HTML, normalises links, produces typed article blocks, a section tree and a compact search index. The iOS app reads only the bundled package through `ManualStore`; SwiftData persists bookmarks, notes, reading history and vehicle profiles separately.

**Tech Stack:** Swift 6.0+, SwiftUI, SwiftData, Foundation, `NSRegularExpression`, ImageIO where available; iOS 17.0 minimum; no network or third-party dependencies.

## Constraints

- All manual reading, images and search work offline; no `WKWebView`.
- Russian is the current UI language; strings and models are localisation-ready.
- The manual package is replaceable and never contains user data.
- Decode content and images lazily; malformed source content yields diagnostics, not crashes.
- Never use force unwraps in production code.

## File map

| Area | Responsibility |
| --- | --- |
| `Importer/Sources/ManualImporter` | Import pipeline, HTML normalisation, index and CLI entry point |
| `Resources/ManualBundle` | Demonstration `manual.json`, `search-index.json` and copied images after import |
| `Models` | Codable manual-package and SwiftData user models |
| `Data/ManualStore` | Package decoder, in-memory section/article lookup, background search |
| `Data/UserStore` | SwiftData schema and user-data export |
| `Features/*` | SwiftUI screens grouped by product feature |
| `Shared` | Styles, accessibility and image viewing primitives |
| `Tests` and `Importer/Tests` | Unit and UI coverage |

## Implementation tasks

### 1. Verify the importer contract

- [ ] Write importer tests for link normalisation, Russian token indexing, tree construction, and HTML block extraction.
- [ ] Run `swift test` and confirm the tests fail because the importer module is absent.
- [ ] Implement only the package data models and pure transformations needed by the tests.
- [ ] Re-run `swift test` and confirm all importer tests pass.

### 2. Build the replaceable manual package

- [ ] Add `accord-manual-import` executable with `--input`, `--output` and `--demo` options.
- [ ] Prefer `catalog/pages.json`; discover HTML below `site/` when that optional catalogue is unavailable.
- [ ] Emit `manual.json`, `search-index.json`, `metadata.json`, `diagnostics.json`, and only referenced image files.
- [ ] Run the importer against `accord-manual-full` and create the bounded demo bundle committed to `Resources/ManualBundle`.

### 3. Implement app data boundaries

- [ ] Define immutable manual DTOs in `Models/ManualModels.swift` and user-only SwiftData entities in `Models/UserModels.swift`.
- [ ] Implement `ManualStore` actor and `SearchService` with cancellation-safe debounced queries.
- [ ] Add tests covering load failure, search ranking and filters.

### 4. Implement navigation and article reading

- [ ] Add `AccordManualApp`, dependency container and four-tab root UI.
- [ ] Implement compact phone navigation and iPad `NavigationSplitView` section/article layout.
- [ ] Render semantic blocks as SwiftUI views, including collapsible procedure groups, article contents, native links, unavailable links, bookmarks, notes, reading position and related articles.

### 5. Implement search, saved content and settings

- [ ] Implement grouped, debounced local search with histories and filters.
- [ ] Implement favourites, notes and history with native deletion confirmation and undo.
- [ ] Add vehicle profile, appearance, readable-spacing, package information, local backup/export and local diagnostic report creation.

### 6. Implement image experiences and accessibility

- [ ] Add lazy bundle image loading with a bounded cache and graceful missing-image state.
- [ ] Add native full-screen zoom/pan image viewer, double-tap zoom, share sheet and gallery.
- [ ] Add labels, hints and scalable typography to all principal controls.

### 7. Verify and document

- [ ] Add unit tests and XCTest UI flow tests.
- [ ] Run `swift test` and `xcodebuild test` where a full Xcode installation is available.
- [ ] Write a README using the actual generated targets and commands; document import limitations and package format.
