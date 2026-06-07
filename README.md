# LLMWikiPDFReader

Lightweight research PDF reader for JJukE's LLM Wiki workflow.

## v1 behavior

- macOS SwiftUI app using PDFKit.
- Four fixed highlight colors:
  - Red: highest-level concept
  - Green: secondary high-level concept
  - Yellow: detailed-level concept
  - Blue: limitations/problems
- Stores annotation source data as sidecar JSON in `raw/reader-annotations/`.
- Exports Obsidian-friendly Markdown into `raw/papers/`.
- Does not mutate original PDF files.
- Keeps Zotero integration read-only for v1. The current resolver accepts Zotero PDFs from shared iCloud through the normal file picker and infers Zotero item links when the PDF path includes an item-key folder.
- Persists security-scoped PDF bookmark data when macOS provides it.
- Maintains PDF Back/Forward history for intentional scroll sessions, page jumps, and highlight jumps.
- Sidebar highlight rows navigate to the stored highlight location in the PDF.

## v2 iCloud sync foundation

- Sidecar JSON now uses schema version 2 for new documents while preserving v1 decode compatibility.
- PDFs can record a `pdf_relative_path` when opened from the selected iCloud Drive Obsidian vault, so different devices can resolve the same vault file without sharing absolute local paths.
- Annotation saves merge with any existing sidecar before writing, preserving independent highlights from other devices.
- Deleted highlights write tombstones under `deleted_annotations`, preventing older iCloud sidecars from restoring removed highlights.
- Autosave now saves the merged sidecar and regenerates the Obsidian Markdown note.
- The macOS app observes the open sidecar file and redraws highlights when iCloud Drive updates it.
- The app target includes an iOS/iPadOS SwiftUI entry and UIKit/PDFKit view scaffold for opening vault PDFs through Files and rendering synced highlights.

## Module layout

- `AnnotationCore`: shared paper metadata, annotations, color semantics, JSON persistence, and Markdown rendering.
- `VaultExporter`: vault-relative Markdown and sidecar export into the LLM Wiki folder layout.
- `ZoteroResolver`: read-only Zotero PDF path and metadata inference.
- `LLMWikiPDFReader`: macOS SwiftUI/PDFKit shell.
- `AnnotationCoreSmokeTests`: framework-independent verification runner for environments where XCTest is unavailable.

## Run

```bash
cd /Users/jjuke/Desktop/dev/LLMWikiPDFReader
swift run LLMWikiPDFReader
```

In the app:

1. Choose this vault as the vault root.
2. Open a PDF from the shared iCloud Zotero folder.
3. Select text and use `Cmd+1`, `Cmd+2`, `Cmd+3`, or `Cmd+4` to highlight.
4. Use the sidebar highlight list to jump back to stored highlight locations.
5. Use `Cmd+[` and `Cmd+]` to move through reader navigation history.
6. Export Markdown when you want an Obsidian/LLM-Wiki note.

## Check

```bash
cd /Users/jjuke/Desktop/dev/LLMWikiPDFReader
swift build
swift run AnnotationCoreSmokeTests
```

## Install Local App

```bash
cd /Users/jjuke/Desktop/dev/LLMWikiPDFReader
./scripts/install_local_app.sh
open "$HOME/Applications/LLMWikiPDFReader.app"
```

To keep it in the Dock, launch the app, right-click its Dock icon, then choose `Options > Keep in Dock`.

The install script builds a release executable, bundles the app icon from `Resources/AppIcon.icns`, and writes the app to `$HOME/Applications/LLMWikiPDFReader.app`.

## Reader navigation

Back/Forward history uses normalized visible PDF position rather than raw scroll pixels. Intentional scroll sessions are detected at about `0.5` pages per second; after scrolling stops for 1 second, one history entry is added for the location before that scroll session. This keeps a fast scroll from page 4 to page 1 as one Back step instead of many tiny steps.

Explicit navigation, such as page jumps and sidebar highlight jumps, records the current location before moving. Clicking highlighted text inside the PDF selects it without adding a navigation jump.

## Data contract

The sidecar JSON has this stable shape:

```json
{
  "schema_version": 1,
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

## Future iPhone/iPad path

`AnnotationCore`, `VaultExporter`, and `ZoteroResolver` are platform-neutral. The v2 scaffold adds a UIKit/PDFKit view and iOS app entry, but touch-native highlight creation and conflict UI still need product work before the mobile app is feature-complete.
