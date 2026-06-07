#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_skill="$repo_root/skills/switch-mode"
target_root="${CODEX_HOME:-$HOME/.codex}/skills"
target_skill="$target_root/switch-mode"

if [[ ! -d "$source_skill" ]]; then
    echo "Missing repo skill source: $source_skill" >&2
    exit 1
fi

mkdir -p "$target_root"

if [[ -L "$target_skill" ]]; then
    current_target="$(readlink "$target_skill")"
    if [[ "$current_target" == "$source_skill" ]]; then
        echo "$target_skill already points to $source_skill"
        exit 0
    fi
    backup="$target_skill.backup.$(date +%Y%m%d%H%M%S)"
    mv "$target_skill" "$backup"
    echo "Moved existing skill symlink to $backup"
elif [[ -e "$target_skill" ]]; then
    backup="$target_skill.backup.$(date +%Y%m%d%H%M%S)"
    mv "$target_skill" "$backup"
    echo "Moved existing skill to $backup"
fi

ln -s "$source_skill" "$target_skill"
echo "Installed $target_skill -> $source_skill"
