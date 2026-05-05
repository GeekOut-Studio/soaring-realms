--!strict

--[=[
	@class RequirementInventoryHasRoomForEach
	Constructs a `Requirement` that's satisfied when the player can fit at least
	one of *every* listed item kind into their inventory. Use this when the
	producing action's outcome could be any of several drops and the action is
	only safe to start if every possible drop has somewhere to land — for example
	a weighted ore-node drop where we don't know which drop will roll.

	The fit check is delegated to `InventoryShared.CanFitOne` (meta-naive: an
	existing partial stack of the same kind counts as room).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryShared = require(ReplicatedStorage.Shared.InventoryShared)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

local InventoryHasRoomForEach = {}

function InventoryHasRoomForEach.Make(itemKinds: { string }): RequirementsTypes.Requirement
	assert(#itemKinds > 0, "InventoryHasRoomForEach requires at least one item kind")
	return {
		Kind = "InventoryHasRoomForEach",
		Check = function(snapshot: RequirementsTypes.PlayerSnapshot): (boolean, string?)
			for _, kind in itemKinds do
				if not InventoryShared.CanFitOne(snapshot.Inventory, kind) then
					return false, "Your inventory is full."
				end
			end
			return true, nil
		end,
	}
end

return InventoryHasRoomForEach
