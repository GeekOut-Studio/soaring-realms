---
name: upload-asset
description: Upload a local asset file (audio, image) to Roblox via the Open Cloud API using rbxcloud, then write the resulting `rbxassetid://` into the appropriate Defs file. Trigger when the user runs `/upload-asset <type> <file> <DefsTable>.<Key>` or asks to upload an asset to Roblox.
---

# upload-asset

Upload one or more local assets to Roblox under the configured group and patch the new asset IDs into the appropriate `src/Shared/Defs/<Defs>.luau` file.

The heavy lifting (rbxcloud submit + operation polling, env loading) lives in `scripts/upload-asset.sh`. This skill orchestrates: call the script, parse its output, edit the Defs file, run `check.sh`.

## Invocation

Two common shapes:

- **Explicit mapping:** `/upload-asset <type> <file> <DefsTable>.<Key>` — caller specifies one file and its target Defs key. Use this when the desired Defs key differs from the filename.
- **Batch / implicit:** the user pastes a list of files and a target Defs table (or it's obvious from context, e.g. `.ogg` → `SoundDefs`). The key for each file is the filename without extension. Use this when key names should mirror filenames — much faster than one invocation per file.

If the target Defs table isn't clear, ask before uploading. Don't guess.

## Steps

1. **Resolve targets.** For each file, decide: the `<DefsTable>` it goes into, and the `<Key>` to write. Default key = filename without extension.
2. **Check no key already exists** in the Defs file. If any do, stop and ask whether to overwrite — pre-existing IDs may be referenced elsewhere.
3. **Run the upload script** in one shot with all files:
   ```bash
   ./scripts/upload-asset.sh <audio|image> <file1> [<file2> ...]
   ```
   The script submits in parallel, polls each operation, and prints one line per file:
   - Success: `<name> rbxassetid://<id>`
   - Failure: `<name> ERROR: <message>`
   The script's exit code is non-zero if any upload failed. Surface failures verbatim to the user; don't retry automatically (most failures are 403/moderation/size and need user intervention).
4. **Patch the Defs file** with the successful results, preserving alphabetical key order. Use the Edit tool against a unique anchor; don't rewrite the file.
5. **Run `./scripts/check.sh src/Shared/Defs/<DefsTable>.luau`** to confirm the file still parses.
6. **Report** to the user: new IDs, the file path edited, and the inserted lines. Don't stage or commit.

## Defs file shapes

- **Plain dict of strings** (e.g. `ImageDefs.luau`):
  ```lua
  return {
      Foo = "rbxassetid://123",
  }
  ```
- **Dict mapped through `Sift.Dictionary.map`** (e.g. `SoundDefs.luau`):
  ```lua
  local Defs = {
      Victory = "rbxassetid://12222253",
      VictoryButLouder = { SoundId = "rbxassetid://12222253", Volume = 2 },
  }
  ```

Always insert as a plain string value: `<Key> = "rbxassetid://<id>",`. Users can convert to the table form (Volume/Looped/etc.) afterward.

## Prereqs (one-time, fail fast if missing)

- `rbxcloud` available on PATH (rokit-managed). If `./scripts/upload-asset.sh --help`-equivalent fails complaining about rbxcloud, tell the user to `rokit add Sleitnick/rbxcloud`.
- `.env.ps1` (or `.env`) in the repo root with `RBXCLOUD_API_KEY` and `ROBLOX_GROUP_ID`. The script reads both.

Don't re-check these before every call; just run the script and surface its error if env is missing.

## Failure modes

- **403 PERMISSION_DENIED / "User not authenticated":** API key issue. Don't retry. Tell the user to check the Creator Dashboard key: `asset:write` scope, the group listed under "Access Permissions", no IP restriction, and the underlying user has "Manage group assets" on the group.
- **Moderation rejection:** the operation comes back `done: true` with an error. Surface verbatim; don't edit Defs.
- **File too large:** Roblox enforces ~7 MB for audio, smaller for decals. Surface the error; suggest shrinking.
- **Network failure mid-upload:** rbxcloud creates a new asset on each retry (no dedup). Ask before retrying — duplicates leak into the group.
- **rbxcloud flag shape changed:** if the script errors on unknown flags, run `rbxcloud assets create --help` and `rbxcloud assets get-operation --help`, fix `scripts/upload-asset.sh`, don't silently guess.

## Out of scope

- Models, meshes, animations.
- User-account uploads (script is hardcoded to `--creator-type group`).
