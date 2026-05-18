--!strict

--[=[
	@class TreeNodeDefs
	Static defs for each kind of tree node placed in the world. Indexed by
	`TreeNodeKind`, which is the value of the `TreeNodeKind` attribute on each
	`TreeNode`-tagged model.

	The `transform` step automatically prepends two requirements every tree node
	shares: `HasEquipmentWithStats("MainHandMelee", "Woodcutting")` (an axe-class
	tool in the melee slot) and `InventoryHasRoomForEach(<drop kinds>)` (room for
	any possible drop). Def authors don't restate either — keeping them in sync
	by hand would be a maintenance trap.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

--[=[
	@type TreeNodeKind "Poplar"
	@within TreeNodeDefs
]=]
export type TreeNodeKind = "Poplar"

--[=[
	@interface DropEntry
	@within TreeNodeDefs
	@field Kind string -- An item kind in `ItemDefs`.
	@field Weight number -- Relative weight in the weighted draw.
]=]
export type DropEntry = {
	Kind: string,
	Weight: number,
}

--[=[
	@type Drops string | {DropEntry}
	@within TreeNodeDefs
	Either an item kind name (always-this-item drop) or a list of weighted entries
	from which one is drawn per progress fill.
]=]
export type Drops = string | { DropEntry }

--[=[
	@interface TreeNodeDef
	@within TreeNodeDefs
	@field Kind TreeNodeKind
	@field Name string -- Human-readable name shown on the proximity prompt.
	@field Requirements {Requirement} -- Woodcutting-attempt gates. Auto-prepended with `HasEquipmentWithStats("Woodcutting")` and `InventoryHasRoomForEach(<drop kinds>)` during `transform`.
	@field ProgressHealth number -- HP drained from the per-player progress meter. Each swing deals `power * EfficiencyMultiplier` damage.
	@field CutHealth number -- HP drained from the shared cut meter. Each contributing swing (stump only) deals `power` damage. Significantly larger than `ProgressHealth`. Filling triggers the trunk to fall and the bonus phase to begin.
	@field ExperiencePerProgress number -- Woodcutting experience awarded each time the per-player progress meter fills.
	@field Drops Drops -- What item is granted when the per-player progress meter fills.
]=]
export type TreeNodeDef = {
	Kind: TreeNodeKind,
	Name: string,
	Requirements: { Requirements.Requirement },
	ProgressHealth: number,
	CutHealth: number,
	ExperiencePerProgress: number,
	Drops: Drops,
}

export type TreeNodeDefs = { [string]: TreeNodeDef }

local Defs = {
	Poplar = {
		Name = "Poplar",
		Requirements = {
			Requirements.SkillLevel("Woodcutting", 1),
		},
		ProgressHealth = 30,
		CutHealth = 600,
		ExperiencePerProgress = 10,
		Drops = "LogPoplar",
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

local function transform(defs): TreeNodeDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		local toolRequirement = Requirements.HasEquipmentWithStats("MainHandMelee", "Woodcutting")
		local roomRequirement = Requirements.InventoryHasRoomForEach(dropsToKinds(def.Drops))
		local requirements = Sift.Array.concat({ toolRequirement, roomRequirement }, def.Requirements)
		return Sift.Dictionary.merge(def, {
			Kind = kind,
			Requirements = requirements,
		})
	end)
end

return transform(Defs)
