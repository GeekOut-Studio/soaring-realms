--!strict

--[=[
	@class RequirementHasEquipmentWithStats
	Constructs a `Requirement` that's satisfied when the item equipped in the
	named slot has a non-nil `ItemDef.Stats[statClass]`. Slot-specific by design:
	if a future feature lets a different slot grant mining ability (e.g. a ring
	in `RingRight`), add a separate requirement for that slot rather than
	loosening this one. Keeping the requirement and the consumer (e.g. `OreNode`)
	pointed at the same slot keeps them from drifting.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

local LabelsByClass: { [string]: string } = {
	Mining = "mining tool",
	Woodcutting = "woodcutting tool",
	Combat = "weapon",
}

local HasEquipmentWithStats = {}

function HasEquipmentWithStats.Make(
	slot: EquipmentTypes.EquipmentSlot,
	statClass: string
): RequirementsTypes.Requirement
	return {
		Kind = "HasEquipmentWithStats",
		Check = function(snapshot: RequirementsTypes.PlayerSnapshot): (boolean, string?)
			local item = snapshot.Equipment[slot]
			if item ~= nil then
				local def = ItemDefs[item.Kind]
				if def ~= nil and def.Stats ~= nil and (def.Stats :: any)[statClass] ~= nil then
					return true, nil
				end
			end
			local label = LabelsByClass[statClass] or statClass
			return false, `You need to equip a {label}.`
		end,
	}
end

return HasEquipmentWithStats
