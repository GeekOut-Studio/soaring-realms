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
	@field Min number -- Inclusive minimum quantity on a successful roll.
	@field Max number -- Inclusive maximum quantity on a successful roll.
	@field Chance number? -- 0..1 probability of this entry hitting. Defaults to 1.
]=]
export type LootEntry = {
	Kind: string,
	Min: number,
	Max: number,
	Chance: number?,
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
