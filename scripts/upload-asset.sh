#!/usr/bin/env bash
# Upload one or more files to Roblox via the Open Cloud Assets API and print
# the resulting asset IDs. Hits apis.roblox.com directly; no rbxcloud dependency.
#
# Usage: ./scripts/upload-asset.sh <type> <file> [<file> ...]
#   <type>: audio | image
#
# Output: one line per file: "<basename-no-ext> rbxassetid://<id>"
#         or "<basename-no-ext> ERROR: <message>" on failure.
# Exit status is non-zero if any upload failed.

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

ENDPOINT="https://apis.roblox.com/assets/v1/assets"
OP_ENDPOINT="https://apis.roblox.com/assets/v1/operations"

# Echoes "<assetType> <mimeType>" or returns non-zero for unsupported combos.
asset_info_for() {
    local kind="$1" file="$2" ext
    ext="$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')"
    case "$kind:$ext" in
        audio:ogg)            echo "Audio audio/ogg" ;;
        audio:mp3)            echo "Audio audio/mpeg" ;;
        audio:flac)            echo "Audio audio/flac" ;;
        audio:wav)            echo "Audio audio/wav" ;;
        image:png)            echo "Image image/png" ;;
        image:jpg|image:jpeg) echo "Image image/jpeg" ;;
        image:bmp)            echo "Image image/bmp" ;;
        image:tga)            echo "Image image/tga" ;;
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

    info="$(asset_info_for "$asset_kind" "$file")" || {
        ops+=("")
        errors+=("unsupported $asset_kind extension: $file")
        continue
    }
    asset_type="${info%% *}"
    content_type="${info##* }"

    boundary="----UploadAssetBoundary$RANDOM$RANDOM"
    body_file="$(mktemp)"
    {
        printf -- "--%s\r\n" "$boundary"
        printf 'Content-Disposition: form-data; name="request"\r\n'
        printf 'Content-Type: application/json\r\n\r\n'
        printf '{"assetType":"%s","displayName":"%s","description":"Uploaded via scripts/upload-asset.sh","creationContext":{"creator":{"groupId":"%s"}}}' \
            "$asset_type" "$name" "$ROBLOX_GROUP_ID"
        printf -- "\r\n--%s\r\n" "$boundary"
        printf 'Content-Disposition: form-data; name="fileContent"; filename="%s"\r\n' "$base"
        printf 'Content-Type: %s\r\n\r\n' "$content_type"
        cat "$file"
        printf -- "\r\n--%s--\r\n" "$boundary"
    } > "$body_file"

    submit_out="$(curl -s -X POST "$ENDPOINT" \
        -H "x-api-key: $ROBLOX_API_KEY" \
        -H "Content-Type: multipart/form-data; boundary=$boundary" \
        --data-binary "@$body_file" 2>&1)"
    submit_status=$?
    rm -f "$body_file"

    if [ "$submit_status" -ne 0 ]; then
        ops+=("")
        errors+=("curl submit failed: $(echo "$submit_out" | tr '\n' ' ')")
        continue
    fi

    op_id="$(echo "$submit_out" | sed -nE 's/.*"operationId"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)"
    if [ -z "$op_id" ]; then
        op_id="$(echo "$submit_out" | sed -nE 's|.*"path"[[:space:]]*:[[:space:]]*"operations/([^"]+)".*|\1|p' | head -n1)"
    fi
    if [ -z "$op_id" ]; then
        ops+=("")
        errors+=("could not parse operation id from: $(echo "$submit_out" | tr '\n' ' ')")
        continue
    fi
    ops+=("$op_id")
    errors+=("")
done

# Poll phase. Up to ~60s per operation, 2s interval.
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
    for _ in $(seq 1 30); do
        poll_out="$(curl -s "$OP_ENDPOINT/$op" -H "x-api-key: $ROBLOX_API_KEY" 2>&1)" || {
            poll_err="poll failed: $(echo "$poll_out" | tr '\n' ' ')"
            break
        }
        if echo "$poll_out" | grep -qE '"done"[[:space:]]*:[[:space:]]*true'; then
            asset_id="$(echo "$poll_out" | sed -nE 's/.*"assetId"[[:space:]]*:[[:space:]]*"?([0-9]+)"?.*/\1/p' | head -n1)"
            if [ -z "$asset_id" ]; then
                poll_err="operation done but no assetId: $(echo "$poll_out" | tr '\n' ' ')"
            fi
            break
        fi
        sleep 2
    done

    if [ -n "$asset_id" ]; then
        echo "$name rbxassetid://$asset_id"
    else
        echo "$name ERROR: ${poll_err:-timed out waiting for operation $op}"
        exit_code=1
    fi
done

exit "$exit_code"
