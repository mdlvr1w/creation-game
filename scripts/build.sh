#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot_binary="${GODOT_BIN:-godot}"
expected_version=4.7.2.stable
version="$("$godot_binary" --version)"
if [[ "$version" != "$expected_version".* ]]; then
    printf 'Expected Godot %s, received %s\n' "$expected_version" "$version" >&2
    exit 1
fi

revision="$(git rev-parse --short HEAD 2>/dev/null || printf unversioned)"
if [[ "$revision" != unversioned ]] && [[ -n "$(git status --porcelain)" ]]; then
    revision="$revision-dirty"
fi
printf '%s\n' "$revision" > game/build_revision.txt

"$godot_binary" --headless --editor --import
"$godot_binary" --headless --script res://tests/figure_test.gd
"$godot_binary" --headless --script res://tests/workspace_test.gd
"$godot_binary" --headless --script res://tests/mannequin_test.gd
"$godot_binary" --headless --script res://tests/movement_test.gd
"$godot_binary" --headless --script res://tests/grab_test.gd
"$godot_binary" --headless --script res://tests/recording_test.gd
"$godot_binary" --headless --fixed-fps 60 --script res://tests/dynamic_movement_test.gd
mkdir -p dist/linux dist/windows
cp notices/GODOT-*.txt dist/linux/
cp notices/GODOT-*.txt dist/windows/
"$godot_binary" --headless --export-release Linux dist/linux/workspace.x86_64
"$godot_binary" --headless --export-release Windows dist/windows/workspace.exe
