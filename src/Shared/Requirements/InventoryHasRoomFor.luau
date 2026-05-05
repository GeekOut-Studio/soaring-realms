--!strict

--[=[
	@class RequirementInventoryHasRoomFor
	Constructs a `Requirement` that's satisfied when the player can fit at least
	one of the listed item kinds into their inventory. Pass an array of kinds when
	the producing action could yield any of several drops (e.g. weighted ore-node
	drops); the requirement passes if *any one* kind in the list can be placed.

	The fit check is delegated to `InventoryShared.CanFitOne`, which is meta-naive
	(an existing partial stack of the same kind counts as room regardless of its
	`Meta`).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryShared = require(ReplicatedStorage.Shared.InventoryShared)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

local InventoryHasRoomFor = {}

function InventoryHasRoomFor.Make(itemKinds: { string }): RequirementsTypes.Requirement
	assert(#itemKinds > 0, "InventoryHasRoomFor requires at least one item kind")
	return {
		Kind = "InventoryHasRoomFor",
		Check = function(snapshot: RequirementsTypes.PlayerSnapshot): (boolean, string?)
			for _, kind in itemKinds do
				if InventoryShared.CanFitOne(snapshot.Inventory, kind) then
					return true, nil
				end
			end
			return false, "Your inventory is full."
		end,
	}
end

return InventoryHasRoomFor
