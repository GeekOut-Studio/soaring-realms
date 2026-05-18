--!strict

--[=[
	@class SkillShared
	Pure deterministic math relating a player's skill level to the mechanical
	effects that level confers. Per-skill functions are grouped into sub-tables
	(`SkillShared.Mining`, etc.) so the module stays browseable as more skills
	gain mechanical effects.

	Functions here must remain pure: input → output, no service calls, no
	`os.time()`. Both client (preview UI, tooltips) and server (authoritative
	rolls) call into the same functions to avoid drift.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)

type MiningStats = ItemStatsTypes.MiningStats
type WoodcuttingStats = ItemStatsTypes.WoodcuttingStats
type FishingStats = ItemStatsTypes.FishingStats

local SkillShared = {}

SkillShared.Mining = {}

local MINING_POWER_PER_LEVEL = 0.02

--[=[
	Returns the effective `(min, max)` power range a player rolls per swing, given
	their base item `MiningStats` and their current Mining level. Each level adds
	`MINING_POWER_PER_LEVEL` (currently 2%) on top of the item's base range.
	@function Mining.GetEffectivePower
	@within SkillShared
	@param stats MiningStats
	@param level number
	@return number -- Effective minimum power.
	@return number -- Effective maximum power.
]=]
function SkillShared.Mining.GetEffectivePower(stats: MiningStats, level: number): (number, number)
	local mult = 1 + level * MINING_POWER_PER_LEVEL
	return stats.Power.Min * mult, stats.Power.Max * mult
end

SkillShared.Woodcutting = {}

local WOODCUTTING_POWER_PER_LEVEL = 0.02

--[=[
	Returns the effective `(min, max)` power range a player rolls per swing, given
	their base item `WoodcuttingStats` and their current Woodcutting level. Each
	level adds `WOODCUTTING_POWER_PER_LEVEL` (currently 2%) on top of the item's
	base range.
	@function Woodcutting.GetEffectivePower
	@within SkillShared
	@param stats WoodcuttingStats
	@param level number
	@return number -- Effective minimum power.
	@return number -- Effective maximum power.
]=]
function SkillShared.Woodcutting.GetEffectivePower(stats: WoodcuttingStats, level: number): (number, number)
	local mult = 1 + level * WOODCUTTING_POWER_PER_LEVEL
	return stats.Power.Min * mult, stats.Power.Max * mult
end

SkillShared.Fishing = {}

local FISHING_CATCH_POWER_PER_LEVEL = 0.02

--[=[
	Returns the effective `(min, max)` catch-power range a player rolls per tick,
	given their base rod `FishingStats` and their current Fishing level. Each
	level adds `FISHING_CATCH_POWER_PER_LEVEL` (currently 2%) on top of the rod's
	base range. The rolled value is used both to derive catch chance (opposed
	against the spot's `CatchDifficulty`) and to advance the spot's frenzy bar.
	@function Fishing.GetEffectiveCatchPower
	@within SkillShared
	@param stats FishingStats
	@param level number
	@return number -- Effective minimum catch power.
	@return number -- Effective maximum catch power.
]=]
function SkillShared.Fishing.GetEffectiveCatchPower(stats: FishingStats, level: number): (number, number)
	local mult = 1 + level * FISHING_CATCH_POWER_PER_LEVEL
	return stats.CatchPower.Min * mult, stats.CatchPower.Max * mult
end

--[=[
	Returns the catch chance for a single tick: `power / (power + difficulty)`.
	An opposed-ratio formula — equal numbers give 50%, doubling power gives ~67%.
	@function Fishing.GetCatchChance
	@within SkillShared
	@param power number -- Rolled catch power for this tick.
	@param difficulty number -- The spot's `CatchDifficulty`.
	@return number -- Catch chance, 0..1.
]=]
function SkillShared.Fishing.GetCatchChance(power: number, difficulty: number): number
	return power / (power + difficulty)
end

return SkillShared
