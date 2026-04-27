--!strict

--[=[
	@class InventoryTypes
	Shared types and constants for the inventory system.
]=]

--[=[
	@interface Item
	@within InventoryTypes
	@field Kind string -- The item kind key, matching an entry in ItemDefs.
	@field Count number? -- Present iff the item's def has MaxStackSize. Omitted for non-stackable items.
	@field Meta {[string]: any}? -- Optional per-item metadata (e.g. durability, enchantments). Stacks only merge if Meta is identical.
]=]
export type Item = {
	Kind: string,
	Count: number?,
	Meta: { [string]: any }?,
}

--[=[
	@type Inventory {[string]: Item}
	@within InventoryTypes
	A player's inventory, keyed by slot number strings (`"1"` through `tostring(InventoryTypes.Size)`).
	Not guaranteed to be contiguous; players may rearrange slots freely.
]=]
export type Inventory = { [string]: Item }

local InventoryTypes = {}

--[=[
	@prop Size number
	@within InventoryTypes
	Total number of inventory slots. Use this constant when iterating all slots.
]=]
InventoryTypes.Size = 30

--[=[
	@prop DefaultInventory Inventory
	@within InventoryTypes
	Empty inventory used as the starting state for new players.
]=]
InventoryTypes.DefaultInventory = table.freeze({} :: Inventory)

return InventoryTypes
