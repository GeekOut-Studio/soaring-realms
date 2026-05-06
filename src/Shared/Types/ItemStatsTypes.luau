--!strict

--[=[
	@class ItemStatsTypes
	Stat blocks that live on an `ItemDef`. Each named sub-table describes the
	item's contribution to a single gameplay class (mining, combat, …).
	Presence of a sub-table is itself meaningful: a requirement like
	`HasEquippedToolWithStats("Mining")` passes iff some equipped item's
	`Stats.Mining` is non-nil.
]=]

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
	@interface Stats
	@within ItemStatsTypes
	@field Mining MiningStats? -- Present on mining tools (pickaxes).
]=]
export type Stats = {
	Mining: MiningStats?,
}

return {}
