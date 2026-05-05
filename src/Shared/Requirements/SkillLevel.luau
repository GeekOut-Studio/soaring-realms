--!strict

--[=[
	@class RequirementSkillLevel
	Constructs a `Requirement` that's satisfied when the player's level in the
	named skill is at least `level`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

local SkillLevel = {}

function SkillLevel.Make(skill: SkillTypes.SkillKind, level: number): RequirementsTypes.Requirement
	return {
		Kind = "SkillLevel",
		Check = function(snapshot: RequirementsTypes.PlayerSnapshot): (boolean, string?)
			local current = snapshot.Skills[skill]
			local currentLevel = if current ~= nil then current.Level else 0
			if currentLevel >= level then
				return true, nil
			end
			return false, `You need {skill} level {level} for this.`
		end,
	}
end

return SkillLevel
