--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local ImageDefs = require(ReplicatedStorage.Shared.Defs.ImageDefs)
local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

export type SkillDef = {
	Kind: SkillTypes.SkillKind,
	Name: string,
	Image: string,
	DisplayOrder: number,
}

export type SkillDefs = { [string]: SkillDef }

local Defs = {
	Strength = {
		Name = "Strength",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 1,
	},
	Dexterity = {
		Name = "Dexterity",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 2,
	},
	Magic = {
		Name = "Magic",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 3,
	},
	Agility = {
		Name = "Agility",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 4,
	},
	Endurance = {
		Name = "Endurance",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 5,
	},
	Mining = {
		Name = "Mining",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 6,
	},
	Smithing = {
		Name = "Smithing",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 7,
	},
	Woodcutting = {
		Name = "Woodcutting",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 8,
	},
	Crafting = {
		Name = "Crafting",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 9,
	},
	Survivalism = {
		Name = "Survivalism",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 10,
	},
	Fishing = {
		Name = "Fishing",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 11,
	},
	Cooking = {
		Name = "Cooking",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 12,
	},
	Enchanting = {
		Name = "Enchanting",
		Image = ImageDefs.UniversalPlaceholder,
		DisplayOrder = 13,
	},
}

local function transform(defs): SkillDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, { Kind = kind })
	end)
end

return transform(Defs)
