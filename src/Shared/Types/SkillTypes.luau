--!strict

--[=[
	@class SkillTypes
	Shared types and constants for the skill system.
]=]

--[=[
	@type SkillKind string
	@within SkillTypes
	String literal union of valid skill kinds.
]=]
export type SkillKind =
	"Strength"
	| "Dexterity"
	| "Magic"
	| "Agility"
	| "Endurance"
	| "Mining"
	| "Smithing"
	| "Woodcutting"
	| "Crafting"
	| "Survivalism"
	| "Fishing"
	| "Cooking"
	| "Enchanting"

--[=[
	@interface Skill
	@within SkillTypes
	@field Level number -- Current level, derived from `Experience` via `SkillExperience.LevelForExperience`.
	@field Experience number -- Total accumulated experience. Monotonically non-decreasing.
]=]
export type Skill = {
	Level: number,
	Experience: number,
}

--[=[
	@type Skills {[string]: Skill}
	@within SkillTypes
	A player's skills, keyed by `SkillKind` name.
]=]
export type Skills = { [string]: Skill }

local SkillTypes = {}

--[=[
	@prop Kinds {SkillKind}
	@within SkillTypes
	Ordered list of every valid skill kind.
]=]
SkillTypes.Kinds = table.freeze({
	"Strength",
	"Dexterity",
	"Magic",
	"Agility",
	"Endurance",
	"Mining",
	"Smithing",
	"Woodcutting",
	"Crafting",
	"Survivalism",
	"Fishing",
	"Cooking",
	"Enchanting",
} :: { SkillKind })

--[=[
	@prop KindSet {[string]: true}
	@within SkillTypes
	Set form of `Kinds` for O(1) membership checks.
]=]
local kindSet: { [string]: true } = {}
for _, kind in SkillTypes.Kinds do
	kindSet[kind] = true
end
SkillTypes.KindSet = table.freeze(kindSet)

--[=[
	@prop DefaultSkills Skills
	@within SkillTypes
	Default starting skills: every `SkillKind` initialized to `{Level = 1, Experience = 0}`.
]=]
local defaults: Skills = {}
for _, kind in SkillTypes.Kinds do
	defaults[kind] = { Level = 1, Experience = 0 }
end
SkillTypes.DefaultSkills = table.freeze(defaults)

return SkillTypes
