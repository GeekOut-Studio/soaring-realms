# Rules

- Run `stylua <file>` on every modified Lua or Luau file.
- Use PascalCase for module tables, their public methods, and exported names. Use camelCase for private module-level functions and local variables within a scope. No underscore prefixes for private members.
- Prefer `x ~= nil` / `x == nil` over `not x` / `if x` when the intent is a nil check.
