--!strict

--[=[
	@class ItemStatsTypes
	Stat blocks that live on an `ItemDef`. Each named sub-table describes the
	item's contribution to a single gameplay class (mining, combat, …).
	Presence of a sub-table is itself meaningful: a requirement like
	`HasEquippedToolWithStats("Mining")` passes iff some equipped item's
	`Stats.Mining` is non-nil.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageTypes = require(ReplicatedStorage.Shared.Types.DamageTypes)

--[=[
	@interface PowerRange
	@within ItemStatsTypes
	@field Min number
	@field Max number
]=]
export type PowerRange = {
	Min: number,
	Max: number,
}

--[=[
	@interface MiningStats
	@within ItemStatsTypes
	@field Interval number -- Seconds between successive swings.
	@field Power PowerRange -- Per-swing damage range applied to ore-node progress and break meters. One value is rolled per swing and used for both meters.
]=]
export type MiningStats = {
	Interval: number,
	Power: PowerRange,
}

--[=[
	@interface CombatStats
	@within ItemStatsTypes
	@field Interval number -- Seconds between successive attacks.
	@field Power PowerRange -- Per-swing damage range. One value is rolled per swing and applied to the target.
	@field Range number -- Stud distance within which a target is considered in reach.
	@field DamageType DamageType -- Damage type tag passed through `DamageServer`.
	@field AttackAnimation string? -- `AnimationDefs` key played by the wielder on each swing.
]=]
export type CombatStats = {
	Interval: number,
	Power: PowerRange,
	Range: number,
	DamageType: DamageTypes.DamageType,
	AttackAnimation: string?,
}

--[=[
	@interface Stats
	@within ItemStatsTypes
	@field Mining MiningStats? -- Present on mining tools (pickaxes).
	@field Combat CombatStats? -- Present on weapons.
]=]
export type Stats = {
	Mining: MiningStats?,
	Combat: CombatStats?,
}

return {}
