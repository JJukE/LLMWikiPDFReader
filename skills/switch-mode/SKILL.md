---
name: switch-mode
description: Switch a codebase between local re-install mode and GitHub-safe version management mode. Use when the user explicitly invokes `$switch-mode`, says "Switch the codebase to re-install mode.", says "Switch the codebase to version management mode.", or asks to prepare LLMWikiPDFReader signing settings for local iPhone/iPad reinstallations or public GitHub commits.
---

# Switch Mode

## Workflow

First inspect the current repository. If the working directory is `LLMWikiPDFReader`, follow this skill's project-specific workflow. For other repositories, read the nearest `AGENTS.md` and apply the same concept only if it defines compatible operating modes.

Use `re-install mode` for local signed app runs and repeated device reinstallations. Use `version management mode` before commits, pull requests, or GitHub pushes.

## LLMWikiPDFReader

The skill source lives in `skills/switch-mode/` inside this repository. Its mode policy lives in `AGENTS.md`.

For re-install mode:

1. Ask the user for private signing inputs if they are not already provided in the current turn.
2. Required private inputs are `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`.
3. Do not store private values in the skill, repo documentation, examples, or logs beyond the current tool call output.
4. Run the helper script with `--mode reinstall` and the private values.

For version management mode:

1. Run the helper script with `--mode version-management`.
2. Run the GitHub hygiene checks listed in `AGENTS.md`.
3. Report any remaining private metadata matches instead of guessing they are safe.

Use dry-run first when the user asks to preview changes, when the working tree contains unrelated changes, or when the requested mode is ambiguous.

## Helper Script

Run from the repository root:

```bash
python3 skills/switch-mode/scripts/switch_llmwiki_pdfreader_mode.py --mode version-management --dry-run
```

Re-install mode example, using values supplied by the user:

```bash
python3 skills/switch-mode/scripts/switch_llmwiki_pdfreader_mode.py --mode reinstall --development-team ABCDE12345 --bundle-id com.example.private.LLMWikiPDFReader
```

Version management mode:

```bash
python3 skills/switch-mode/scripts/switch_llmwiki_pdfreader_mode.py --mode version-management
```

To make `$switch-mode` discoverable as a normal local Codex skill on a Mac, run:

```bash
./scripts/install_repo_skills.sh
```

The helper script only changes the app target Debug and Release signing fields in `LLMWikiPDFReader/LLMWikiPDFReader.xcodeproj/project.pbxproj`.
