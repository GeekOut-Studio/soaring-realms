# Rules

- Run `stylua <file>` on every modified Lua or Luau file.
- Use PascalCase for module tables, their public methods, exported names, and all instance fields (`self.*`). Use camelCase only for private module-level functions and purely local variables within a function scope. No underscore prefixes for private members.
- Prefer `x ~= nil` / `x == nil` over `not x` / `if x` when the intent is a nil check.
- Edit code by modifying files in this repository, not via the Roblox Studio MCP. The repo is synced into Studio via Rojo.
- Use absolute `require` paths whenever possible — start from a service like `ReplicatedStorage` or `ServerScriptService` (e.g. `require(ServerScriptService.Server.Servers.DataServer)`), not relative paths like `script.Parent.DataServer`. The only acceptable exception is when the path must be resolved at runtime via `:WaitForChild` because the target may not yet exist.
- Document public interfaces (module functions, exported types, public properties) with Moonwave-style `--[=[...]=]` block comments. Plain `--` comments are fine for private helpers and inline logic notes. Moonwave tag usage:
  - `@class <Name>` — top of every public module table. All other doc comments in that file use `@within <Name>`.
  - `@prop <name> <type>` — module-level constants and properties.
  - `@interface <Name>` — exported table types with named fields. Follow with one `@field <name> <type>` line per field; add a trailing `--` description on the same line when the field needs explanation.
  - `@type <Name> <type>` — type aliases only (union types, dictionary types, primitive aliases). Do NOT use for named-field tables; use `@interface` instead.
  - `@param <name> <type>` / `@return <type>` — function parameters and return values.
  - `@yields` — mark functions that yield.
  - `@server` / `@client` — when a function is realm-restricted.