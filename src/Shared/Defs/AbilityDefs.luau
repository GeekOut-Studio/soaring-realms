--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)
local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

export type AbilityDef = AbilityTypes.AbilityDef
export type AbilityDefs = { [string]: AbilityDef }

local Defs = {
	BasicAttackMainHandMelee = {
		Handler = "BasicAttackWeaponMelee",
		Config = {
			Slot = "MainHandMelee",
		},
		Costs = {},
		Cooldown = 1.0,
		CooldownGroup = "MainHandMelee",
		Requirements = {
			Requirements.HasEquipmentWithStats("MainHandMelee", "Combat"),
		},
		Targeting = { Kind = "None" },
	},

	DenizenMelee = {
		Handler = "DenizenMelee",
		Config = {},
		Costs = {},
		Cooldown = 1.0,
		Requirements = {},
		Targeting = { Kind = "None" },
	},
}

local function transform(defs): AbilityDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, { Kind = kind })
	end)
end

return transform(Defs)
