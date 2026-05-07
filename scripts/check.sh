#!/usr/bin/env bash
# Format and type-check Luau files. Pass file paths as args.
#
# Usage: ./scripts/check.sh src/foo.luau src/bar.luau

set -e

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <file.luau> [file.luau ...]" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

global_types=/tmp/globalTypes.d.luau
if [ ! -f "$global_types" ]; then
    curl -fsSL -o "$global_types" \
        https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

rojo sourcemap default.project.json --output sourcemap.json >/dev/null

stylua "$@"

luau-lsp analyze \
    --sourcemap=sourcemap.json \
    --defs="$global_types" \
    --platform=roblox \
    --no-strict-dm-types \
    --ignore="Packages/**" \
    --ignore="**/_Index/**" \
    "$@"

# Validate Moonwave doc comments. The extractor errors on malformed blocks,
# mismatched @param/@return tags, and unknown tags. Its `extract` subcommand
# only accepts a single input path per invocation, so loop over the files.
# Output JSON is discarded — we only care about the exit code.
for file in "$@"; do
    moonwave-extractor extract "$file" >/dev/null
done
