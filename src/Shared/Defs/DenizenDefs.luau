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

--[=[
	@interface Animations
	@within DenizenDefs
	@field Idle string? -- `AnimationDefs` key looped over the denizen's lifetime.
	@field Run string? -- `AnimationDefs` key played whenever the denizen is moving. Layers over `Idle` via `AnimationPriority`.
]=]
export type Animations = {
	Idle: string?,
	Run: string?,
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
]=]
export type DenizenDef = {
	Kind: string,
	Name: string,
	MaxHealth: number,
	MoveSpeed: number,
	Animations: Animations,
	Team: string?,
	Behavior: BehaviorDef?,
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
		},
		Team = "Enemies",
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
					AttackRange = 4,
					LeashRange = 30,
					AttackCooldown = 1.2,
					AttackDamage = 8,
					AttackKind = "Slashing",
					AttackAnimation = "ImpAttack",
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
				-- After healing up while fleeing, go back to wandering.
				{ From = "Fleeing", When = { Kind = "HealthAbove", Fraction = 0.7 } :: any, Goto = "Idle" },
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
