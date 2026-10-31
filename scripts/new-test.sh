#!/bin/bash
# Creates a test file for a new feature from the template, and adds it to the project.
#   scripts/new-test.sh Bookmarks            -> Tests/MDEditTests/Features/BookmarksTests.swift
#   scripts/new-test.sh Importer Safety      -> Tests/MDEditTests/Safety/ImporterTests.swift
# Folders: Features (what it does), Safety (files and edits), Security (hostile input), Performance (speed budgets).
set -e
cd "$(dirname "$0")/.."
name="$1"; dir="${2:-Features}"
[ -n "$name" ] || { echo "usage: scripts/new-test.sh FeatureName [Features|Safety|Security|Performance]"; exit 2; }
file="Tests/MDEditTests/$dir/${name}Tests.swift"
[ ! -e "$file" ] || { echo "$file already exists"; exit 1; }
mkdir -p "Tests/MDEditTests/$dir"
sed "s/__NAME__/$name/g" scripts/test-template.swift.txt > "$file"
xcodegen generate >/dev/null
echo "created $file — fill in the TODOs, then: make test T=${name}Tests"
