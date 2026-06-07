#!/usr/bin/env python3
"""Switch LLMWikiPDFReader Xcode signing fields between local and public modes."""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path


PUBLIC_BUNDLE_ID = "com.example.LLMWikiPDFReader"
PROJECT_RELATIVE_PATH = Path("LLMWikiPDFReader/LLMWikiPDFReader.xcodeproj/project.pbxproj")
ANNOTATIONS_FOLDER_DEFAULT_KEY = '"INFOPLIST_KEY_LLMWikiDefaultAnnotationsFolderPath[sdk=iphoneos*]"'
DEFAULT_PDF_FOLDER_KEY = '"INFOPLIST_KEY_LLMWikiDefaultPDFDirectoryPath[sdk=iphoneos*]"'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Switch LLMWikiPDFReader app-target signing fields."
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path.cwd(),
        help="Path to the LLMWikiPDFReader repository root. Defaults to cwd.",
    )
    parser.add_argument(
        "--mode",
        choices=("reinstall", "version-management"),
        required=True,
        help="Mode to apply.",
    )
    parser.add_argument(
        "--development-team",
        help="Private Apple DEVELOPMENT_TEAM value. Required for reinstall mode.",
    )
    parser.add_argument(
        "--bundle-id",
        help="Private PRODUCT_BUNDLE_IDENTIFIER value. Required for reinstall mode.",
    )
    parser.add_argument(
        "--annotations-folder-default",
        help="Private iPhone/iPad default annotations folder path. Required for reinstall mode.",
    )
    parser.add_argument(
        "--default-pdf-folder",
        help="Private iPhone/iPad default PDF folder path. Required for reinstall mode.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print a unified diff without writing the project file.",
    )
    return parser.parse_args()


def validate_reinstall_inputs(
    development_team: str | None,
    bundle_id: str | None,
    annotations_folder_default: str | None,
    default_pdf_folder: str | None,
) -> None:
    if not development_team:
        raise SystemExit("--development-team is required for reinstall mode")
    if not bundle_id:
        raise SystemExit("--bundle-id is required for reinstall mode")
    if not annotations_folder_default:
        raise SystemExit("--annotations-folder-default is required for reinstall mode")
    if not default_pdf_folder:
        raise SystemExit("--default-pdf-folder is required for reinstall mode")
    if not re.fullmatch(r"[A-Za-z0-9]{10}", development_team):
        raise SystemExit("--development-team should be a 10-character Apple team ID")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]", bundle_id):
        raise SystemExit("--bundle-id is not a valid bundle identifier shape")
    if ".." in bundle_id or "." not in bundle_id:
        raise SystemExit("--bundle-id must contain dot-separated identifier components")
    if not annotations_folder_default.startswith("/"):
        raise SystemExit("--annotations-folder-default must be an absolute path")
    if not default_pdf_folder.startswith("/"):
        raise SystemExit("--default-pdf-folder must be an absolute path")


def find_block_end(lines: list[str], start: int) -> int:
    depth = 0
    for index in range(start, len(lines)):
        depth += lines[index].count("{")
        depth -= lines[index].count("}")
        if depth == 0 and index > start:
            return index
    raise SystemExit("Could not parse XCBuildConfiguration block")


def is_app_build_configuration(block: list[str]) -> bool:
    joined = "".join(block)
    return (
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" in joined
        and "ENABLE_USER_SELECTED_FILES = readonly;" in joined
        and "PRODUCT_NAME = \"$(TARGET_NAME)\";" in joined
    )


def set_or_insert_setting(block: list[str], key: str, value: str, after_key: str) -> list[str]:
    setting_re = re.compile(rf"^(\s*){re.escape(key)} = .*;\n$")
    for index, line in enumerate(block):
        match = setting_re.match(line)
        if match:
            block[index] = f"{match.group(1)}{key} = {value};\n"
            return block

    after_re = re.compile(rf"^(\s*){re.escape(after_key)} = .*;\n$")
    for index, line in enumerate(block):
        match = after_re.match(line)
        if match:
            block.insert(index + 1, f"{match.group(1)}{key} = {value};\n")
            return block

    raise SystemExit(f"Could not find insertion point for {key}")


def remove_setting(block: list[str], key: str) -> list[str]:
    setting_re = re.compile(rf"^\s*{re.escape(key)} = .*;\n$")
    return [line for line in block if not setting_re.match(line)]


def quote_build_setting_value(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def update_app_block(
    block: list[str],
    mode: str,
    development_team: str | None,
    bundle_id: str | None,
    annotations_folder_default: str | None,
    default_pdf_folder: str | None,
) -> list[str]:
    updated = list(block)
    if mode == "reinstall":
        updated = set_or_insert_setting(
            updated,
            "DEVELOPMENT_TEAM",
            development_team or "",
            "CURRENT_PROJECT_VERSION",
        )
        updated = set_or_insert_setting(
            updated,
            "PRODUCT_BUNDLE_IDENTIFIER",
            bundle_id or "",
            "MARKETING_VERSION",
        )
        updated = set_or_insert_setting(
            updated,
            ANNOTATIONS_FOLDER_DEFAULT_KEY,
            quote_build_setting_value(annotations_folder_default or ""),
            "GENERATE_INFOPLIST_FILE",
        )
        updated = set_or_insert_setting(
            updated,
            DEFAULT_PDF_FOLDER_KEY,
            quote_build_setting_value(default_pdf_folder or ""),
            ANNOTATIONS_FOLDER_DEFAULT_KEY,
        )
        return updated

    updated = remove_setting(updated, "DEVELOPMENT_TEAM")
    updated = remove_setting(updated, ANNOTATIONS_FOLDER_DEFAULT_KEY)
    updated = remove_setting(updated, DEFAULT_PDF_FOLDER_KEY)
    updated = set_or_insert_setting(
        updated,
        "PRODUCT_BUNDLE_IDENTIFIER",
        PUBLIC_BUNDLE_ID,
        "MARKETING_VERSION",
    )
    return updated


def transform_project(
    text: str,
    mode: str,
    development_team: str | None,
    bundle_id: str | None,
    annotations_folder_default: str | None,
    default_pdf_folder: str | None,
) -> tuple[str, int]:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    index = 0
    changed_blocks = 0

    while index < len(lines):
        if (
            " = {" not in lines[index]
            or index + 1 >= len(lines)
            or "isa = XCBuildConfiguration;" not in lines[index + 1]
        ):
            output.append(lines[index])
            index += 1
            continue

        end = find_block_end(lines, index)
        block = lines[index : end + 1]
        if is_app_build_configuration(block):
            block = update_app_block(
                block,
                mode,
                development_team,
                bundle_id,
                annotations_folder_default,
                default_pdf_folder,
            )
            changed_blocks += 1

        output.extend(block)
        index = end + 1

    if changed_blocks != 2:
        raise SystemExit(
            f"Expected to update 2 app build configurations, updated {changed_blocks}"
        )
    return "".join(output), changed_blocks


def main() -> int:
    args = parse_args()
    if args.mode == "reinstall":
        validate_reinstall_inputs(
            args.development_team,
            args.bundle_id,
            args.annotations_folder_default,
            args.default_pdf_folder,
        )

    repo = args.repo.expanduser().resolve()
    project_file = repo / PROJECT_RELATIVE_PATH
    if not project_file.exists():
        raise SystemExit(f"Project file not found: {project_file}")

    original = project_file.read_text()
    updated, changed_blocks = transform_project(
        original,
        args.mode,
        args.development_team,
        args.bundle_id,
        args.annotations_folder_default,
        args.default_pdf_folder,
    )

    if original == updated:
        print(f"No changes needed; {changed_blocks} app build configurations already match.")
        return 0

    diff = "".join(
        difflib.unified_diff(
            original.splitlines(keepends=True),
            updated.splitlines(keepends=True),
            fromfile=str(project_file),
            tofile=str(project_file),
        )
    )
    if args.dry_run:
        print(diff, end="")
        return 0

    project_file.write_text(updated)
    print(f"Updated {changed_blocks} app build configurations in {project_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
