--!strict

--[=[
	@class RequirementInventoryHasRoomFor
	Constructs a `Requirement` that's satisfied when the player can fit at least
	one of the listed item kinds into their inventory. Pass an array of kinds when
	the producing action could yield any of several drops (e.g. weighted ore-node
	drops); the requirement passes if *any one* kind in the list can be placed.

	For stackable items, "fits" means an empty slot OR an existing partial stack
	of the same kind with capacity remaining. For non-stackable items, only an
	empty slot counts.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

local InventoryHasRoomFor = {}

local function canFitOne(inventory: InventoryTypes.Inventory, itemKind: string): boolean
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

function InventoryHasRoomFor.Make(itemKinds: { string }): RequirementsTypes.Requirement
	assert(#itemKinds > 0, "InventoryHasRoomFor requires at least one item kind")
	return {
		Kind = "InventoryHasRoomFor",
		Check = function(snapshot: RequirementsTypes.PlayerSnapshot): (boolean, string?)
			for _, kind in itemKinds do
				if canFitOne(snapshot.Inventory, kind) then
					return true, nil
				end
			end
			return false, "Your inventory is full."
		end,
	}
end

return InventoryHasRoomFor
