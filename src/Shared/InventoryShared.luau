--!strict

--[=[
	@class InventoryShared
	Pure-function helpers operating on `Inventory` state. Shared between
	`InventoryServer` (which mutates the canonical state) and other modules that
	need to reason about inventory capacity in either realm — notably the
	`InventoryHasRoomFor` requirement, which runs both server-side via
	`RequirementsServer` and client-side via `RequirementsClient`.

	No side effects, no mutation: every function takes an inventory snapshot and
	returns a value.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

local InventoryShared = {}

--[=[
	Recursive deep equality used to determine whether two `Meta` tables match,
	and therefore whether two stacks of the same kind can be merged.
	@within InventoryShared
	@param a {[string]: any}?
	@param b {[string]: any}?
	@return boolean
]=]
function InventoryShared.MetaEqual(a: { [string]: any }?, b: { [string]: any }?): boolean
	if a == b then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	for k, v in a do
		local bv = b[k]
		if type(v) == "table" then
			if not InventoryShared.MetaEqual(v :: any, bv :: any) then
				return false
			end
		elseif bv ~= v then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

--[=[
	Returns the number of empty slots in `inventory`.
	@within InventoryShared
	@param inventory Inventory
	@return number
]=]
function InventoryShared.CountFreeSlots(inventory: InventoryTypes.Inventory): number
	local count = 0
	for i = 1, InventoryTypes.Size do
		if inventory[tostring(i)] == nil then
			count += 1
		end
	end
	return count
end

--[=[
	Returns whether `inventory` has room for at least one of `itemKind`.

	Meta-naive: an existing partial stack of the same kind counts as room
	regardless of its `Meta`. Use `StackableCapacity` when meta-aware merging
	behavior is required (e.g. AddItem's actual placement logic).
	@within InventoryShared
	@param inventory Inventory
	@param itemKind string
	@return boolean
]=]
function InventoryShared.CanFitOne(inventory: InventoryTypes.Inventory, itemKind: string): boolean
	local def = ItemDefs[itemKind]
	if def == nil then
		return false
	end
	if def.MaxStackSize ~= nil then
		for i = 1, InventoryTypes.Size do
			local item = inventory[tostring(i)]
			if item == nil then
				return true
			end
			if item.Kind == itemKind and (item.Count or 0) < def.MaxStackSize then
				return true
			end
		end
		return false
	end
	for i = 1, InventoryTypes.Size do
		if inventory[tostring(i)] == nil then
			return true
		end
	end
	return false
end

--[=[
	Computes how many more items of a stackable `itemKind` with matching `meta`
	can fit. Counts both empty slots (a full stack's worth each) and existing
	partial stacks of the same kind+meta (remaining capacity each).
	@within InventoryShared
	@param inventory Inventory
	@param itemKind string
	@param maxStackSize number
	@param meta {[string]: any}?
	@return number
]=]
function InventoryShared.StackableCapacity(
	inventory: InventoryTypes.Inventory,
	itemKind: string,
	maxStackSize: number,
	meta: { [string]: any }?
): number
	local capacity = 0
	for i = 1, InventoryTypes.Size do
		local item = inventory[tostring(i)]
		if item == nil then
			capacity += maxStackSize
		elseif item.Kind == itemKind and InventoryShared.MetaEqual(item.Meta, meta) then
			capacity += maxStackSize - (item.Count or 0)
		end
	end
	return capacity
end

return InventoryShared
