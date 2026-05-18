#!/usr/bin/env bash
# Upload one or more asset files to Roblox via rbxcloud and print the resulting
# asset IDs. Does NOT touch any Defs file — the caller patches those in.
#
# Usage: ./scripts/upload-asset.sh <type> <file> [<file> ...]
#   <type>: audio | image
#
# Output: one line per file, in the form "<basename-no-ext> rbxassetid://<id>"
# (or "<basename-no-ext> ERROR: <message>" on failure). Exits non-zero if any
# upload failed.

set -u

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <audio|image> <file> [file ...]" >&2
    exit 2
fi

asset_kind="$1"
shift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Load env. Prefer .env (bash) but fall back to parsing .env.ps1 so we don't
# have to maintain two copies of the secret.
if [ -f .env ]; then
    # shellcheck disable=SC1091
    . ./.env
elif [ -f .env.ps1 ]; then
    # Parse '$env:NAME = "value"' lines.
    while IFS= read -r line; do
        # shellcheck disable=SC2001
        kv="$(echo "$line" | sed -nE 's/^\$env:([A-Z_]+)[[:space:]]*=[[:space:]]*"([^"]*)".*/\1=\2/p')"
        if [ -n "$kv" ]; then
            export "${kv?}"
        fi
    done < .env.ps1
fi

if [ -z "${RBXCLOUD_API_KEY:-}" ]; then
    echo "RBXCLOUD_API_KEY not set (looked in .env and .env.ps1)" >&2
    exit 1
fi
if [ -z "${ROBLOX_GROUP_ID:-}" ]; then
    echo "ROBLOX_GROUP_ID not set" >&2
    exit 1
fi

asset_type_for() {
    local kind="$1" file="$2" ext
    ext="$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')"
    case "$kind:$ext" in
        audio:ogg)         echo audio-ogg ;;
        audio:mp3)         echo audio-mp3 ;;
        audio:flac)        echo audio-flac ;;
        audio:wav)         echo audio-wav ;;
        image:png)         echo decal-png ;;
        image:jpg|image:jpeg) echo decal-jpeg ;;
        image:bmp)         echo decal-bmp ;;
        image:tga)         echo decal-tga ;;
        *) return 1 ;;
    esac
}

# Submit phase: kick off all uploads in parallel, collect operation IDs.
declare -a names files ops errors
for file in "$@"; do
    base="$(basename "$file")"
    name="${base%.*}"
    names+=("$name")
    files+=("$file")

    if [ ! -f "$file" ]; then
        ops+=("")
        errors+=("file not found: $file")
        continue
    fi

    at="$(asset_type_for "$asset_kind" "$file")" || {
        ops+=("")
        errors+=("unsupported $asset_kind extension: $file")
        continue
    }

    submit_out="$(rbxcloud assets create \
        --asset-type "$at" \
        --display-name "$name" \
        --description "Uploaded via scripts/upload-asset.sh" \
        --filepath "$file" \
        --creator-id "$ROBLOX_GROUP_ID" \
        --creator-type group 2>&1)" || {
        ops+=("")
        errors+=("submit failed: $(echo "$submit_out" | tr '\n' ' ')")
        continue
    }

    # Response is either {"path":"operations/<id>", ...} or already-resolved.
    op_id="$(echo "$submit_out" | sed -nE 's/.*"path"[[:space:]]*:[[:space:]]*"operations\/([^"]+)".*/\1/p' | head -n1)"
    if [ -z "$op_id" ]; then
        ops+=("")
        errors+=("could not parse operation id from: $(echo "$submit_out" | tr '\n' ' ')")
        continue
    fi
    ops+=("$op_id")
    errors+=("")
done

# Poll phase. Up to ~60s per operation, 3s interval.
exit_code=0
for i in "${!names[@]}"; do
    name="${names[$i]}"
    op="${ops[$i]}"
    err="${errors[$i]}"

    if [ -n "$err" ]; then
        echo "$name ERROR: $err"
        exit_code=1
        continue
    fi

    asset_id=""
    poll_err=""
    for _ in $(seq 1 20); do
        poll_out="$(rbxcloud assets get-operation --operation-id "$op" 2>&1)" || {
            poll_err="poll failed: $(echo "$poll_out" | tr '\n' ' ')"
            break
        }
        done_flag="$(echo "$poll_out" | sed -nE 's/.*"done"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' | head -n1)"
        if [ "$done_flag" = "true" ]; then
            asset_id="$(echo "$poll_out" | sed -nE 's/.*"assetId"[[:space:]]*:[[:space:]]*"?([0-9]+)"?.*/\1/p' | head -n1)"
            if [ -z "$asset_id" ]; then
                poll_err="operation done but no assetId: $(echo "$poll_out" | tr '\n' ' ')"
            fi
            break
        fi
        sleep 3
    done

    if [ -n "$asset_id" ]; then
        echo "$name rbxassetid://$asset_id"
    else
        echo "$name ERROR: ${poll_err:-timed out waiting for operation $op}"
        exit_code=1
    fi
done

exit "$exit_code"
