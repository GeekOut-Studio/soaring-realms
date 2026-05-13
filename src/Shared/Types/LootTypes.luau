--!strict

--[=[
	@class LootTypes
	Types for the denizen loot system: tables defined on `DenizenDef`,
	per-entry rolls, and the per-player `PlayerLoot` array that fills a
	`LootBag` after a kill. `PlayerLoot` is intentionally an array of the
	same `Item` shape used by `Inventory` so per-item metadata
	(durability, affixes) can flow through unchanged when those features
	land.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

--[=[
	@interface LootEntry
	@within LootTypes
	@field Kind string -- `ItemDefs` key.
	@field Chance number? -- 0..1 probability of this entry hitting. Defaults to 1.
	@field Min number? -- Range form, inclusive minimum. Used iff both `Min` and `Max` are set.
	@field Max number? -- Range form, inclusive maximum. Used iff both `Min` and `Max` are set.
	@field Count number? -- Fixed quantity. Used when the range form isn't fully specified. Defaults to 1.

	Each entry picks one of two quantity-rolling forms at runtime:
	- **Range:** both `Min` and `Max` set; rolled count is uniform on `[Min, Max]`.
	- **Fixed:** otherwise; rolled count is `Count` (or `1` if omitted).

	The forms aren't expressed as a union type because Luau's analyzer
	can't reliably resolve table-literal unions branch-by-branch — a
	type-level "either both Min/Max or just Count" would force every
	def-site to ship an annotation. The flat all-optional shape is the
	pragmatic price; the runtime in `LootShared.RollLootTable` enforces
	the form discrimination.
]=]
export type LootEntry = {
	Kind: string,
	Chance: number?,
	Min: number?,
	Max: number?,
	Count: number?,
}

--[=[
	@type LootTable {LootEntry}
	@within LootTypes
	Ordered list of independent per-entry rolls. Each entry rolls its
	`Chance` separately and contributes 0+ items to the result.
]=]
export type LootTable = { LootEntry }

--[=[
	@type PlayerLoot {Item}
	@within LootTypes
	A single player's rolled loot, expressed as a plain array of the same
	`Item` shape used in `Inventory`. Not slot-keyed — the loot bag has
	no notion of slots.
]=]
export type PlayerLoot = { InventoryTypes.Item }

return {}
