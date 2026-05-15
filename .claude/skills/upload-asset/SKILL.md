---
name: upload-asset
description: Upload a local asset file (audio, image) to Roblox via the Open Cloud API using rbxcloud, then write the resulting `rbxassetid://` into the appropriate Defs file. Trigger when the user runs `/upload-asset <type> <file> <DefsTable>.<Key>` or asks to upload an asset to Roblox.
---

# upload-asset

Upload a local asset to Roblox under the configured Roblox group and patch the new asset ID into the appropriate `src/Shared/Defs/<Defs>.luau` file.

## Invocation

```
/upload-asset <type> <file> <DefsTable>.<Key>
```

- `<type>`: `audio` or `image`.
- `<file>`: path to the local asset (relative to repo root or absolute).
- `<DefsTable>.<Key>`: where to write the ID. e.g. `SoundDefs.Victory` → file `src/Shared/Defs/SoundDefs.luau`, key `Victory`.

Example: `/upload-asset audio ./assets/victory.ogg SoundDefs.Victory`

## Preconditions — verify before uploading

Run these checks first. If any fail, stop and tell the user how to fix it; do not attempt the upload.

1. **rbxcloud is installed.** Run `rbxcloud --version`. If it errors with a rokit "not in manifest" message, instruct the user to run `rokit add Sleitnick/rbxcloud` and commit the rokit.toml change. Do not install it for them.
2. **`RBXCLOUD_API_KEY` is set.** Check `$env:RBXCLOUD_API_KEY` (PowerShell). If empty, tell the user to set it for the current shell (`$env:RBXCLOUD_API_KEY = "..."`) — never echo the key back, never write it to a file, never accept it via chat.
3. **`ROBLOX_GROUP_ID` is set.** Check `$env:ROBLOX_GROUP_ID`. This is the numeric Roblox group ID that owns the uploads. If empty, ask the user for the group ID and have them set the env var; don't hardcode it in the skill or repo.
4. **The source file exists** at the supplied path.
5. **The target Defs file exists** at `src/Shared/Defs/<DefsTable>.luau`. If not, stop — don't create it; ask the user.
6. **The target key does not already exist** in the Defs table. If it does, stop and ask whether to overwrite. Pre-existing IDs may be referenced elsewhere; replacing them silently is dangerous.

## Upload command

`rbxcloud` requires the asset type to encode the file format. Pick the value matching `<type>` *and* the source file's extension:

| `<type>` + extension       | `--asset-type` |
|----------------------------|----------------|
| `audio` + `.ogg`           | `audio-ogg`    |
| `audio` + `.mp3`           | `audio-mp3`    |
| `audio` + `.flac`          | `audio-flac`   |
| `audio` + `.wav`           | `audio-wav`    |
| `image` + `.png`           | `decal-png`    |
| `image` + `.jpg` / `.jpeg` | `decal-jpeg`   |
| `image` + `.bmp`           | `decal-bmp`    |
| `image` + `.tga`           | `decal-tga`    |

`.env.ps1` must be dot-sourced inside the same command, because each PowerShell tool call is a fresh shell:

```powershell
. .\.env.ps1; rbxcloud assets create `
  --asset-type <AssetType> `
  --display-name "<Key>" `
  --description "Uploaded via /upload-asset" `
  --filepath "<file>" `
  --creator-id $env:ROBLOX_GROUP_ID `
  --creator-type group `
  --pretty
```

`rbxcloud` picks up the API key from `$env:RBXCLOUD_API_KEY` automatically; never pass it on the command line.

If the command fails with `403 PERMISSION_DENIED / User not authenticated`, do **not** retry. The cause is almost always the API key configuration on the Creator Dashboard: missing `asset:write` scope, missing the group under "Access Permissions", an IP restriction, or the underlying user lacking the "Manage group assets" role on the group. Tell the user to check those things and stop.

If the flag names differ from above (rbxcloud has changed shape across versions), run `rbxcloud assets create --help` once, then update this skill file with the corrected flags before retrying. Do not silently guess.

## Parsing the result

`assets create` returns an **operation**, not an asset. The JSON response shape is:

```json
{ "path": "operations/<uuid>", "done": false, "response": null }
```

You must extract the operation UUID (the part after `operations/`) and poll it with `assets get-operation` until `done: true`. The real asset ID is on the resolved response at `.response.assetId` (also mirrored as `.response.path` → `assets/<id>`).

```powershell
. .\.env.ps1; rbxcloud assets get-operation --operation-id "<uuid>" --pretty
```

Polling cadence: typical audio uploads resolve in 3–15 seconds. Poll every ~3 seconds for up to ~60 seconds total. If still not done after that, stop and tell the user — likely stuck in moderation. Do not edit the Defs file until you have a real `assetId`.

If `done: true` but `response` is null and `error` is non-null, the upload was rejected (usually moderation). Surface the error verbatim and do not edit the Defs file.

Batching: when uploading multiple files, submit all `assets create` calls first in parallel (they're independent), collect operation UUIDs, then poll each. This is much faster than serializing submit→poll→submit→poll.

## Writing into the Defs file

The Defs files are either:

- **Plain dict of strings** — e.g. `ImageDefs.luau`:
  ```lua
  return {
      Foo = "rbxassetid://123",
  }
  ```
- **Dict mapped through `Sift.Dictionary.map`** — e.g. `SoundDefs.luau`, where each value is a string SoundId or a table of Sound properties:
  ```lua
  local Defs = {
      Victory = "rbxassetid://12222253",
      VictoryButLouder = { SoundId = "rbxassetid://12222253", Volume = 2 },
  }
  ```

In both shapes the insertion point is the literal `Defs` table (or the returned table in plain dicts). Insert the new entry as a simple string value: `<Key> = "rbxassetid://<id>",`. Place it so the keys remain in alphabetical order — that's the existing convention in `SoundDefs.luau` and `ImageDefs.luau`. If the user wants a table form (custom Volume, Looped, etc.), they'll edit it after.

Use the Edit tool with a unique anchor (the surrounding existing entry or `local Defs = {`). Do not rewrite the whole file.

## After the edit

1. Run `./scripts/check.sh src/Shared/Defs/<DefsTable>.luau` to confirm the file still parses, types check, and doc comments validate.
2. Report to the user: the new asset ID, the file path that was edited, and the line of code that was inserted.
3. Do **not** commit or stage anything. The user controls when changes are committed.

## Failure modes — what to do

- **rbxcloud exits non-zero.** Surface the stderr verbatim. The two common cases: bad API key (401/403) and bad creator/group ID. Do not retry automatically.
- **Asset moderation rejection.** Some uploads (especially audio) get auto-rejected. Tell the user; the file isn't edited.
- **File too large.** Roblox enforces per-asset-type size limits (audio ~7 MB, decals smaller). Surface the rbxcloud error; suggest the user shrink the file.
- **Network failure mid-upload.** Re-running is safe — rbxcloud creates a new asset each time, it does not deduplicate. Warn the user that retrying without confirmation can leak duplicate assets and ask before retrying.

## Out of scope

- Models, meshes, animations — not supported by this skill yet. If the user asks, tell them to extend this skill rather than improvising the upload.
- User-account uploads — this skill is hardcoded to group uploads. Switching to a user would mean changing `--creator-type` and the env var name; ask before changing.
- Bulk / batch upload — one file per invocation. A staged-folder workflow is a separate skill.
