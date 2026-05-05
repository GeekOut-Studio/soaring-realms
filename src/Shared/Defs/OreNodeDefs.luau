--!strict

--[=[
	@class OreNodeDefs
	Static defs for each kind of ore node placed in the world. Indexed by
	`OreNodeKind`, which is the value of the `OreNodeKind` attribute on each
	`OreNode`-tagged model.

	The `transform` step automatically prepends an `InventoryHasRoomForEach`
	requirement derived from each def's `Drops`. Def authors don't need to mirror
	the drop list into a manual requirement — keeping the two in sync would be a
	maintenance trap.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

--[=[
	@type OreNodeKind "Stone" | "Copper"
	@within OreNodeDefs
]=]
export type OreNodeKind = "Stone" | "Copper"

--[=[
	@interface DropEntry
	@within OreNodeDefs
	@field Kind string -- An item kind in `ItemDefs`.
	@field Weight number -- Relative weight in the weighted draw.
]=]
export type DropEntry = {
	Kind: string,
	Weight: number,
}

--[=[
	@type Drops string | {DropEntry}
	@within OreNodeDefs
	Either an item kind name (always-this-item drop) or a list of weighted entries
	from which one is drawn per progress fill.
]=]
export type Drops = string | { DropEntry }

--[=[
	@interface OreNodeDef
	@within OreNodeDefs
	@field Kind OreNodeKind
	@field Name string -- Human-readable name shown on the proximity prompt.
	@field Requirements {Requirement} -- Mining-attempt gates. Auto-prepended with `InventoryHasRoomForEach(<drop kinds>)` during `transform`.
	@field ProgressDifficulty number -- Average seconds for a solo player to fill the per-player progress meter.
	@field BreakDifficulty number -- Average seconds for a solo player to fill the shared break meter (significantly larger than `ProgressDifficulty`).
	@field ExperiencePerProgress number -- Mining experience awarded each time the per-player progress meter fills.
	@field Drops Drops -- What item is granted when the per-player progress meter fills.
]=]
export type OreNodeDef = {
	Kind: OreNodeKind,
	Name: string,
	Requirements: { Requirements.Requirement },
	ProgressDifficulty: number,
	BreakDifficulty: number,
	ExperiencePerProgress: number,
	Drops: Drops,
}

export type OreNodeDefs = { [string]: OreNodeDef }

local Defs = {
	Stone = {
		Name = "Stone",
		Requirements = {
			Requirements.SkillLevel("Mining", 1),
		},
		ProgressDifficulty = 5,
		BreakDifficulty = 25,
		ExperiencePerProgress = 10,
		Drops = "Stone",
	},
	Copper = {
		Name = "Copper",
		Requirements = {
			Requirements.SkillLevel("Mining", 1),
		},
		ProgressDifficulty = 5,
		BreakDifficulty = 25,
		ExperiencePerProgress = 10,
		Drops = {
			{ Kind = "OreCopper", Weight = 3 },
			{ Kind = "Stone", Weight = 1 },
		},
	},
}

local function dropsToKinds(drops: Drops): { string }
	if typeof(drops) == "string" then
		return { drops }
	end
	return Sift.Array.map(drops, function(entry)
		return entry.Kind
	end)
end

local function transform(defs): OreNodeDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		local autoRequirement = Requirements.InventoryHasRoomForEach(dropsToKinds(def.Drops))
		local requirements = Sift.Array.concat({ autoRequirement }, def.Requirements)
		return Sift.Dictionary.merge(def, {
			Kind = kind,
			Requirements = requirements,
		})
	end)
end

return transform(Defs)
