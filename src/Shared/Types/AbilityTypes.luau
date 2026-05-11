--!strict

--[=[
	@class AbilityTypes
	Type contracts for the ability system.

	An ability is the unit of an activator-initiated action: a basic weapon swing,
	a learned skill, a craftable item placement. Each def is a static record
	describing what the ability needs (Requirements, Costs, Cooldown, Targeting)
	and how to run it (Handler + Config). The runtime lives in the matching
	`Server/Abilities/<Handler>.luau` module.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

--[=[
	@interface AbilityActivator
	@within AbilityTypes
	@field GetTeam (AbilityActivator) -> string? -- Combatant teaming. `nil` = hostile to all.
	@field GetCFrame (AbilityActivator) -> CFrame -- Combatant position + facing.
	@field GetHealth (AbilityActivator) -> number -- Current health; `<= 0` means dead.
	@field CombatSession CombatSession? -- Current combat session; `nil` when out of combat.
	@field AnimationPlay (AbilityActivator, kind: string) -> () -- Plays the named animation on the activator.
	@field FaceTowards (AbilityActivator, point: Vector3) -> () -- Pivots the activator to face `point` horizontally. Implementation differs by rig (Outworlder uses `PivotTo`; Denizen uses `ControllerManager.FacingDirection`).

	The minimal contract a handler can rely on. Handler-specific accessors
	(e.g. `Outworlder:GetCombatStats(slot)`) are intentionally **not** part of
	this interface — handlers that need them cast or narrow internally, so the
	choice of where stats come from doesn't leak into the universal contract.
]=]
export type AbilityActivator = {
	GetTeam: (AbilityActivator) -> string?,
	GetCFrame: (AbilityActivator) -> CFrame,
	GetHealth: (AbilityActivator) -> number,
	CombatSession: CombatTypes.CombatSession?,
	AnimationPlay: (AbilityActivator, kind: string) -> (),
	FaceTowards: (AbilityActivator, point: Vector3) -> (),
}

--[=[
	@interface Costs
	@within AbilityTypes
	@field Stamina number? -- Stamina deducted from the activator's `Outworlder.Stamina` on activation. nil = no stamina cost.
	@field Items {[string]: number}? -- Map of item kind → count consumed from the activator's inventory. nil = no item cost.
]=]
export type Costs = {
	Stamina: number?,
	Items: { [string]: number }?,
}

--[=[
	@type TargetingSpec {Kind: "None"}
	@within AbilityTypes
	Declares the input shape an ability needs from the player before it can fire.
	The discriminated table will grow as new targeting modes appear
	(`{Kind = "GroundPoint", MaxRange = number}`, `{Kind = "WorldPoint", ...}`,
	`{Kind = "Combatant", ...}`, etc.). Only `"None"` is wired today —
	`AbilityServer.Activate` takes no client-provided context for it.
]=]
export type TargetingSpec = {
	Kind: "None",
}

--[=[
	@interface AbilityDef
	@within AbilityTypes
	@field Kind string -- Stable identifier; matches the table key in `AbilityDefs`.
	@field Handler string -- Selects the runtime module at `ServerScriptService.Server.Abilities.<Handler>`.
	@field Config {[string]: any} -- Handler-specific configuration. Schema is defined by the handler module.
	@field Costs Costs -- Resources consumed atomically on activation. Use an empty table for no cost.
	@field Cooldown number -- Base seconds before the ability (or its cooldown group) can be activated again. `OnWillCooldown` on the handler may override per-activation.
	@field CooldownGroup string? -- nil = the ability has its own per-Kind cooldown. Otherwise abilities sharing a CooldownGroup share a single cooldown timer per activator.
	@field Requirements {Requirement} -- Standard requirements composed via `Requirements.*`.
	@field Targeting TargetingSpec -- What input the player must provide before activation. Drives client input flows.
]=]
export type AbilityDef = {
	Kind: string,
	Handler: string,
	Config: { [string]: any },
	Costs: Costs,
	Cooldown: number,
	CooldownGroup: string?,
	Requirements: { Requirements.Requirement },
	Targeting: TargetingSpec,
}

--[=[
	@interface AbilityHandler
	@within AbilityTypes
	@field Activate (activator: AbilityActivator, config: any, context: any) -> () -- The handler's main entry point. `context` is the per-activation payload — shape is handler-specific.
	@field OnWillCooldown ((baseCooldown: number, activator: AbilityActivator, config: any, context: any) -> number)? -- Optional cooldown transform. Receives the def's base cooldown; returns the cooldown to apply for this activation.

	Returned by every `Server/Abilities/<Handler>.luau` module. Handlers
	may use more specific internal types for `activator`, `config`, and
	`context` via narrowing; at the registry boundary they're `any`.
]=]
export type AbilityHandler = {
	Activate: (activator: AbilityActivator, config: any, context: any) -> (),
	OnWillCooldown: ((baseCooldown: number, activator: AbilityActivator, config: any, context: any) -> number)?,
}

return {}
