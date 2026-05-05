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

rojo sourcemap default.project.json --output sourcemap.json >/dev/null

stylua "$@"

luau-lsp analyze \
    --sourcemap=sourcemap.json \
    --defs=/tmp/globalTypes.d.luau \
    --platform=roblox \
    --no-strict-dm-types \
    --ignore="Packages/**" \
    --ignore="**/_Index/**" \
    "$@"
