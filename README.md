# LLMWikiPDFReader

Lightweight research PDF reader for JJukE's LLM Wiki workflow, with native Mac and iPhone/iPad apps.

## Features

- Reads PDFs with PDFKit and does not mutate original PDF files.
- Stores app-owned highlight data as sidecar JSON in the configured annotations folder.
- Uses four fixed semantic highlight colors:
  - Red: highest-level concept
  - Green: secondary high-level concept
  - Yellow: detailed-level concept
  - Blue: limitations/problems
- Merges sidecar JSON before saving, preserving independent highlights from synced devices.
- Writes deleted highlights as tombstones under `deleted_annotations`, preventing older sidecars from restoring removed highlights.
- Records `pdf_relative_path` when the PDF is inside the annotations folder, so synced devices can resolve the same vault file without sharing absolute paths.
- Keeps Zotero integration read-only and infers Zotero item links from item-key folders when the PDF is inside the configured Zotero root.

## Mac App

- SwiftUI app with a PDF reader, status bar, and sidebar highlight list.
- Select text and add semantic highlights with toolbar color buttons or `Cmd+1` through `Cmd+4`.
- Remove the selected app highlight with the trash button or the remove-highlight shortcut.
- Open PDFs through the file picker, optionally starting in a configured default PDF folder.
- Configure settings for annotations folder, PDF continuous scrolling, page breaks, Back/Forward shortcut keys, and default Open PDF folder.
- Navigate reader history with Back/Forward buttons or `Cmd+[` and `Cmd+]`.
- Jump from sidebar highlight rows back to the stored PDF location.
- Export Obsidian-friendly Markdown notes into `raw/papers/`.
- Observe the open sidecar file and redraw highlights when iCloud Drive or another device updates it.
- Persist security-scoped PDF and folder bookmarks when macOS provides them.

## iPhone/iPad App

- SwiftUI/UIKit PDFKit app for iPhone and iPad through the Xcode `LLMWikiPDFReader` scheme.
- Shows the same gear-shaped Settings button before setup and while reading.
- Requires an annotations folder before `Open PDF` is enabled, keeping sidecars separate from source PDFs.
- Provides mobile settings for annotations folder, PDF continuous scrolling, page breaks, and default Open PDF folder.
- Opens folders with the iOS document picker and stores matching bookmark/path settings.
- Opens PDFs through Files, loads existing sidecar JSON, and redraws synced highlights.
- Supports touch text selection for creating highlights with the same four semantic colors.
- Removes the selected app highlight and saves tombstones to the sidecar.
- Provides toolbar Back/Forward buttons that track meaningful reader viewport moves.
- Stores the default PDF folder for parity with Mac; the system Files picker may still choose its own starting location.

## Module Layout

- `AnnotationCore`: shared paper metadata, annotations, color semantics, JSON persistence, merge logic, and Markdown rendering.
- `VaultExporter`: vault-relative Markdown and sidecar export into the LLM Wiki folder layout.
- `ZoteroResolver`: read-only Zotero PDF path and metadata inference.
- `LLMWikiPDFReader`: shared SwiftUI/PDFKit app sources for Mac, iPhone, and iPad.
- `LLMWikiPDFReaderMac`: local SwiftPM package runner for Mac development.
- `AnnotationCoreSmokeTests`: framework-independent verification runner for environments where XCTest is unavailable.

## Run

For Xcode device runs, select the `LLMWikiPDFReader` scheme. That scheme builds the signed native app bundle and is the one to use for iPhone, iPad, and Mac destinations.

The SwiftPM executable product is named `LLMWikiPDFReaderMac`; use it only for local package-based Mac runs.

```bash
swift run LLMWikiPDFReaderMac
```

Mac workflow:

1. Choose the annotations folder where sidecar JSON files should be saved.
2. Open a PDF.
3. Select text and use `Cmd+1`, `Cmd+2`, `Cmd+3`, or `Cmd+4` to highlight.
4. Use the sidebar highlight list to jump back to stored highlight locations.
5. Use Back/Forward controls to move through reader navigation history.
6. Export Markdown when you want an Obsidian/LLM-Wiki note.

iPhone/iPad workflow:

1. Tap Settings and choose the annotations folder.
2. Tap `Open PDF` and pick a PDF from Files.
3. Select text in the PDF and create highlights from the mobile toolbar.
4. Use Back/Forward controls to move through reader navigation history.
5. Reopen the same PDF after iCloud sync to load merged sidecar highlights.

## Check

Use the `pdfreader` conda environment for local checks.

```bash
conda run -n pdfreader swift build
conda run -n pdfreader swift run AnnotationCoreSmokeTests
```

## Install Local Mac App

```bash
./scripts/install_local_app.sh
open "$HOME/Applications/LLMWikiPDFReader.app"
```

To keep it in the Dock, launch the app, right-click its Dock icon, then choose `Options > Keep in Dock`.

The install script builds a release executable, bundles the app icon from `Resources/AppIcon.icns`, and writes the app to `$HOME/Applications/LLMWikiPDFReader.app`.

## Reader Navigation

Back/Forward history uses normalized visible PDF position rather than raw scroll pixels. Intentional scroll sessions are detected at about `0.5` pages per second; after scrolling stops for 1 second, one history entry is added for the location before that scroll session. This keeps a fast scroll from page 4 to page 1 as one Back step instead of many tiny steps.

Explicit navigation, such as page jumps and sidebar highlight jumps, records the current location before moving. Clicking highlighted text inside the PDF selects it without adding a navigation jump.

## Public Repo Notes

- Xcode signing is intentionally not tied to a checked-in Apple developer team. Set your own team and bundle identifier in Xcode before device runs or App Store/TestFlight distribution.
- Do not commit provisioning profiles, certificates, private keys, `.env` files, generated app bundles, or local Xcode user data.
- Keep exported vault data under paths such as `raw/reader-annotations/` and `raw/papers/` out of the repo unless it is intentionally added as a fixture.

## Data Contract

The sidecar JSON has this stable shape:

```json
{
  "schema_version": 2,
  "paper": {
    "title": "Paper title",
    "authors": [],
    "year": "2026",
    "citekey": null,
    "zotero_item_key": null,
    "zotero_select_uri": null,
    "pdf_path": "/path/to/paper.pdf",
    "pdf_relative_path": "raw/pdfs/paper.pdf",
    "pdf_bookmark": null
  },
  "annotations": [
    {
      "id": "UUID",
      "page": 1,
      "color": "red",
      "semantic_level": "highest-level concept",
      "selected_text": "Highlighted text",
      "comment": "",
      "created_at": "ISO-8601",
      "updated_at": "ISO-8601",
      "bbox": []
    }
  ],
  "deleted_annotations": [
    {
      "id": "UUID",
      "deleted_at": "ISO-8601"
    }
  ],
  "exports": {
    "obsidian_note_path": "raw/papers/example.md",
    "wiki_page_path": null
  }
}
```
