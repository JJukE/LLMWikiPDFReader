# LLM Wiki PDF Reader

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
4. Export Markdown when you want an Obsidian/LLM-Wiki note.

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
open "$HOME/Applications/LLM Wiki PDF Reader.app"
```

To keep it in the Dock, launch the app, right-click its Dock icon, then choose `Options > Keep in Dock`.

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
  "exports": {
    "obsidian_note_path": "raw/papers/example.md",
    "wiki_page_path": null
  }
}
```

## Future iPhone/iPad path

`AnnotationCore` is platform-neutral. The app-specific PDFKit wrapper is currently macOS-only, so iPhone/iPad support should add UIKit/PDFKit views while reusing the same JSON and Markdown export code.
