# Rules

- Run `stylua <file>` on every modified Lua or Luau file.
- Use PascalCase for module tables, their public methods, exported names, and all instance fields (`self.*`). Use camelCase only for private module-level functions and purely local variables within a function scope. No underscore prefixes for private members.
- Prefer `x ~= nil` / `x == nil` over `not x` / `if x` when the intent is a nil check.
- Edit code by modifying files in this repository, not via the Roblox Studio MCP. The repo is synced into Studio via Rojo.
- Document public interfaces (module functions, exported types, public properties) with Moonwave-style `--[=[...]=]` block comments. Use `@class`, `@within`, `@param`, `@return`, `@prop`, and `@type` tags as appropriate. Plain `--` comments are fine for private helpers and inline logic notes.