--!strict

--[=[
	@class RequirementEquipped
	Constructs a `Requirement` that's satisfied when the player has the named item
	kind equipped in the named equipment slot.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

local Equipped = {}

function Equipped.Make(slot: EquipmentTypes.EquipmentSlot, itemKind: string): RequirementsTypes.Requirement
	return {
		Kind = "Equipped",
		Check = function(snapshot: RequirementsTypes.PlayerSnapshot): (boolean, string?)
			local item = snapshot.Equipment[slot]
			if item ~= nil and item.Kind == itemKind then
				return true, nil
			end
			local def = ItemDefs[itemKind]
			local label = if def ~= nil then def.Name else itemKind
			return false, `You need to equip a {label}.`
		end,
	}
end

return Equipped
