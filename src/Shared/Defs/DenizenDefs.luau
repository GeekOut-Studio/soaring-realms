--!strict

--[=[
	@class DenizenDefs
	Static defs for each kind of Denizen — the non-player combat-capable inhabitants of the
	realm (cows, imps, NPCs, …). Indexed by a string `Kind`, which is the value of the
	`DenizenKind` attribute on each `Denizen`-tagged model. No string-literal union: we
	expect hundreds of kinds, so we follow the `ItemDefs` precedent of plain string keys.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)
local LootTypes = require(ReplicatedStorage.Shared.Types.LootTypes)

--[=[
	@interface Animations
	@within DenizenDefs
	@field Idle string? -- `AnimationDefs` key looped over the denizen's lifetime.
	@field Run string? -- `AnimationDefs` key played whenever the denizen is moving. Layers over `Idle` via `AnimationPriority`.
	@field Death string? -- `AnimationDefs` key played once on death by the `DenizenCorpse` component before the model is destroyed. Expected to be non-looping.
]=]
export type Animations = {
	Idle: string?,
	Run: string?,
	Death: string?,
}

--[=[
	@interface DenizenDef
	@within DenizenDefs
	@field Kind string -- The defs key. Auto-filled by `transform`; def authors don't restate it.
	@field Name string -- Human-readable label.
	@field MaxHealth number
	@field MoveSpeed number -- Studs/second. Seeds `ControllerManager.BaseMoveSpeed`.
	@field Animations Animations
	@field Team string? -- Combat team identifier. `nil` means hostile to everyone. Two teams currently exist: `"Players"` and `"Enemies"`.
	@field Behavior BehaviorDef? -- Optional FSM definition consumed by the server-side `Behavior` runner. Omit for static denizens.
	@field CombatStats CombatStats? -- Optional. Per-denizen combat numbers (Interval/Power/Range/DamageType/AttackAnimation) read by ability handlers (e.g. `DenizenMelee`) when the denizen activates an attack ability. Omit for denizens that never attack.
	@field LootTable LootTable? -- Optional. Per-eligible-player loot roll table consumed by `Denizen:Die` → `LootShared.RollLootTable`. Omit for denizens that drop nothing.
]=]
export type DenizenDef = {
	Kind: string,
	Name: string,
	MaxHealth: number,
	MoveSpeed: number,
	Animations: Animations,
	Team: string?,
	Behavior: BehaviorDef?,
	CombatStats: ItemStatsTypes.CombatStats?,
	LootTable: LootTypes.LootTable?,
}

--[=[
	@interface BehaviorDef
	@within DenizenDefs
	@field Initial string -- Name of the state to enter on construction. Must be a key in `States`.
	@field States {[string]: {Kind: string, [string]: any}} -- State configs keyed by state name. The `Kind` field selects an implementation in `Server/Behavior/States/`.
	@field Transitions {{From: string?, When: {Kind: string, [string]: any}, Goto: string}} -- Ordered list of transitions. Evaluated top-to-bottom each tick; first match wins.
]=]
export type BehaviorDef = {
	Initial: string,
	States: { [string]: { Kind: string, [string]: any } },
	Transitions: {
		{
			From: string?,
			When: { Kind: string, [string]: any },
			Goto: string,
		}
	},
}

export type DenizenDefs = { [string]: DenizenDef }

local Defs = {
	Imp = {
		Name = "Imp",
		MaxHealth = 50,
		MoveSpeed = 8,
		Animations = {
			Idle = "ImpIdle",
			Run = "ImpRun",
			Death = "ImpDeath",
		},
		Team = "Enemies",
		CombatStats = {
			Interval = 1.2,
			Power = { Min = 8, Max = 8 },
			Range = 8,
			DamageType = "Slashing",
			AttackAnimation = "ImpAttack",
		},
		LootTable = {
			{ Kind = "Coin", Min = 5, Max = 15 },
		},
		Behavior = {
			Initial = "Idle",
			States = {
				Idle = {
					Kind = "Wander",
					Radius = 12,
					PauseRange = { Min = 2, Max = 5 },
				},
				Aggressing = {
					Kind = "MeleeAggression",
					AttackRange = 8,
					LeashRange = 30,
					Ability = "DenizenMelee",
					OnTargetLost = "Idle",
					OnLeashed = "Returning",
				},
				Returning = {
					Kind = "ReturnToSpawn",
					OnArrive = "Idle",
				},
			},
			Transitions = {
				-- From idle wander, engage anything in sight.
				{ From = "Idle", When = { Kind = "EnemyInRange", Range = 20 } :: any, Goto = "Aggressing" },
			},
		} :: BehaviorDef,
	},
}

local function transform(defs): DenizenDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, { Kind = kind })
	end)
end

return transform(Defs)
