#!/usr/bin/env bash
# Bake inventory icons by uploading per-item .rbxm thumbnails to Roblox.
# See scripts/lune/bake-icons.luau for the heavy lifting.
#
# Usage: ./scripts/bake-icons.sh [path/to/place.rbxlx]

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Mirror upload-asset.sh's env loading so the secret only lives in one place.
if [ -f .env ]; then
    # shellcheck disable=SC1091
    . ./.env
elif [ -f .env.ps1 ]; then
    while IFS= read -r line; do
        # shellcheck disable=SC2001
        kv="$(echo "$line" | sed -nE 's/^\$env:([A-Z_]+)[[:space:]]*=[[:space:]]*"([^"]*)".*/\1=\2/p')"
        if [ -n "$kv" ]; then
            export "${kv?}"
        fi
    done < .env.ps1
fi

if [ -z "${ROBLOX_API_KEY:-}" ]; then
    echo "ROBLOX_API_KEY not set (looked in .env and .env.ps1)" >&2
    exit 1
fi
if [ -z "${ROBLOX_GROUP_ID:-}" ]; then
    echo "ROBLOX_GROUP_ID not set" >&2
    exit 1
fi

lune run scripts/lune/bake-icons.luau "$@"
