--!strict

--[=[
	@class FishingSpotDefs
	Static defs for each kind of fishing spot placed in the world. Indexed by
	`FishingSpotKind`, which is the value of the `FishingSpotKind` attribute on
	each `FishingSpot`-tagged model.

	The `transform` step automatically prepends three requirements every fishing
	spot shares: `HasEquipmentWithStats("MainHandMelee", "Fishing")` (a rod-class
	tool in the melee slot), `InventoryHasRoomForEach(<drop kinds>)` (room for
	any possible drop), and `SkillLevel("Fishing", 1)`. Def authors don't restate
	any of them — keeping them in sync by hand would be a maintenance trap.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

--[=[
	@type FishingSpotKind "Pond"
	@within FishingSpotDefs
]=]
export type FishingSpotKind = "Pond"

--[=[
	@interface DropEntry
	@within FishingSpotDefs
	@field Kind string -- An item kind in `ItemDefs`.
	@field Weight number -- Relative weight in the weighted draw.
]=]
export type DropEntry = {
	Kind: string,
	Weight: number,
}

--[=[
	@type Drops string | {DropEntry}
	@within FishingSpotDefs
	Either an item kind name (always-this-item drop) or a list of weighted entries
	from which one is drawn per successful catch.
]=]
export type Drops = string | { DropEntry }

--[=[
	@interface FishingSpotDef
	@within FishingSpotDefs
	@field Kind FishingSpotKind
	@field Name string -- Human-readable name shown on the proximity prompt.
	@field Requirements {Requirement} -- Fishing-attempt gates. Auto-prepended.
	@field ExperiencePerCatch number -- Fishing experience awarded per successful catch.
	@field FrenzyHealth number -- Ticks of fishing required to fill this spot's frenzy bar while no spot in the group is currently frenzied.
	@field Drops Drops -- What item is granted on a successful catch.
]=]
export type FishingSpotDef = {
	Kind: FishingSpotKind,
	Name: string,
	Requirements: { Requirements.Requirement },
	ExperiencePerCatch: number,
	FrenzyHealth: number,
	Drops: Drops,
}

export type FishingSpotDefs = { [string]: FishingSpotDef }

local Defs = {
	Pond = {
		Name = "Fishing Spot",
		Requirements = {},
		ExperiencePerCatch = 15,
		FrenzyHealth = 1,
		Drops = {
			{ Kind = "FishCommon", Weight = 4 },
			{ Kind = "Junk", Weight = 1 },
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

local function transform(defs): FishingSpotDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		local toolRequirement = Requirements.HasEquipmentWithStats("MainHandMelee", "Fishing")
		local roomRequirement = Requirements.InventoryHasRoomForEach(dropsToKinds(def.Drops))
		local levelRequirement = Requirements.SkillLevel("Fishing", 1)
		local requirements = Sift.Array.concat({ toolRequirement, roomRequirement, levelRequirement }, def.Requirements)
		return Sift.Dictionary.merge(def, {
			Kind = kind,
			Requirements = requirements,
		})
	end)
end

return transform(Defs)
