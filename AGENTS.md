# Repository Guidelines

## Project Structure & Module Organization

This is a Swift Package Manager project for a lightweight PDF reader and export workflow.

- `Package.swift` defines all products and targets.
- `Sources/AnnotationCore/` contains platform-neutral models, color semantics, JSON persistence, metadata guessing, and Markdown rendering.
- `Sources/VaultExporter/` writes sidecar JSON and Obsidian Markdown into the LLM Wiki vault layout.
- `Sources/ZoteroResolver/` infers read-only Zotero metadata from PDF paths.
- `Sources/LLMWikiPDFReader/` contains the SwiftUI/PDFKit macOS app shell.
- `Sources/AnnotationCoreSmokeTests/` is an executable smoke-test runner used instead of XCTest.
- `scripts/` contains local developer utilities, currently app installation.

Generated runtime data belongs under vault paths such as `raw/reader-annotations/` and `raw/papers/`; do not commit user vault exports unless they are intentional fixtures.

## Build, Test, and Development Commands

- Use the `pdfreader` conda environment for this project: `conda activate pdfreader`.
- `swift build` builds all package targets in debug mode.
- `swift run LLMWikiPDFReaderMac` launches the local SwiftPM macOS app runner.
- `swift run AnnotationCoreSmokeTests` checks serialization, Markdown export, vault export, and Zotero path inference.
- `swift build -c release --product LLMWikiPDFReaderMac` builds the release app executable used by the local installer.
- `./scripts/install_local_app.sh` installs a local `.app` bundle into `$HOME/Applications/LLMWikiPDFReader.app`.

Run commands from the repository root inside the `pdfreader` conda environment.

## Coding Style & Naming Conventions

Use Swift 5.9 style with 4-space indentation. Prefer small value types for domain data and descriptive names that match existing terms such as `ReaderDocument`, `HighlightAnnotation`, and `VaultMarkdownExporter`.

File names should match the primary type or feature. Keep platform-neutral logic in `AnnotationCore`; app UI and PDFKit bridging belong in `LLMWikiPDFReader`.

## Testing Guidelines

Add focused checks to `Sources/AnnotationCoreSmokeTests/main.swift` when changing serialization, export formatting, vault paths, or Zotero inference. Name helper tests with the `test...` prefix and keep assertions direct through `expect(...)`.

Before handing off changes, run:

```bash
conda activate pdfreader
swift build
swift run AnnotationCoreSmokeTests
```

## Commit & Pull Request Guidelines

History currently contains one short commit, `Initial LLM Wiki PDF reader`. Use concise, imperative messages such as `Add vault export validation` or `Fix Zotero item key inference`.

Pull requests should include a brief summary, testing performed, and screenshots or screen recordings for visible SwiftUI/PDFKit changes. Link related issues or notes when available, and call out any changes to the sidecar JSON schema or vault output paths.

## Operating Modes

Use `$switch-mode` when the user asks to move between local reinstall work and GitHub-safe version management. The tracked source for this skill lives in `skills/switch-mode/`; run `./scripts/install_repo_skills.sh` on a new Mac to expose it as a normal local Codex skill. The supported commands are:

- `Switch the codebase to re-install mode.`
- `Switch the codebase to version management mode.`

Re-install mode is for local iPhone/iPad or signed Xcode runs from this Mac. Use the Xcode `LLMWikiPDFReader` scheme, set the local Apple development team, use a stable private bundle identifier so iOS treats reinstallations as the same app, and optionally seed iPhone/iPad defaults for the annotations folder and default PDF folder. Private values such as `DEVELOPMENT_TEAM`, personal bundle identifiers, provisioning profile names, certificates, folder default paths, and local absolute paths must come from the user's private notes or direct input for that session. Do not hard-code them in source, docs, or the `$switch-mode` skill; only the mode switch may place them in local uncommitted Xcode project settings.

Version management mode is for preparing commits, pull requests, and GitHub pushes. Restore checked-in signing fields to public-safe values before publishing. The app target bundle identifier should use a placeholder such as `com.example.LLMWikiPDFReader`, and checked-in project files should not contain a personal Apple team ID.

Before pushing to GitHub, check for accidental personal metadata:

```bash
git ls-files -ci --exclude-standard
git ls-files | rg "(xcuserdata|\.DS_Store|\.mobileprovision|\.p12|\.pem|\.key|\.env|Package\.resolved)$"
rg -n "(/Users/|DEVELOPMENT_TEAM|iCloud~QReader)" . --glob '!README.md' --glob '!AGENTS.md' --glob '!*.md'
```

## Security & Configuration Tips

The app must not mutate original PDF files. Keep Zotero integration read-only and preserve security-scoped bookmark behavior on macOS. Avoid hard-coding personal vault paths; accept roots through the app or test-local temporary directories.

Xcode signing is intentionally not tied to a checked-in Apple developer team. Set your own team and bundle identifier locally in Xcode or through `$switch-mode` before device runs, periodic iPhone/iPad reinstallations, or App Store/TestFlight distribution.

Do not commit provisioning profiles, certificates, private keys, `.env` files, generated app bundles, local Xcode user data, or exported vault data under paths such as `raw/reader-annotations/` and `raw/papers/` unless they are intentional fixtures.
