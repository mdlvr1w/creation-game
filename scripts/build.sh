#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
godot_binary="${GODOT_BIN:-godot}"
expected_version=4.5.1.stable
version="$("$godot_binary" --version)"
if [[ "$version" != "$expected_version".* ]]; then
    printf 'Expected Godot %s, received %s\n' "$expected_version" "$version" >&2
    exit 1
fi

"$godot_binary" --headless --editor --import
"$godot_binary" --headless --script res://tests/figure_test.gd
"$godot_binary" --headless --script res://tests/workspace_test.gd
"$godot_binary" --headless --script res://tests/mannequin_test.gd
mkdir -p dist/linux dist/windows
cp notices/GODOT-*.txt dist/linux/
cp notices/GODOT-*.txt dist/windows/
"$godot_binary" --headless --export-release Linux dist/linux/workspace.x86_64
"$godot_binary" --headless --export-release Windows dist/windows/workspace.exe
