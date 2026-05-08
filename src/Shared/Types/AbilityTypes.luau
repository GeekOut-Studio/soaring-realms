--!strict

--[=[
	@class AbilityTypes
	Type contracts for the ability system.

	An ability is the unit of player- (and eventually denizen-) initiated action:
	a basic weapon swing, a learned skill, a craftable item placement. Each def
	is a static record describing what the ability needs (Requirements, Costs,
	Cooldown) and how to run it (Handler + Config). The runtime lives in the
	matching `Server/Abilities/<Handler>.luau` module.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

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
	@interface AbilityDef
	@within AbilityTypes
	@field Kind string -- Stable identifier; matches the table key in `AbilityDefs`. Used as the ability's identity in `AbilityServer.Activate`.
	@field Handler string -- Selects the runtime module at `ServerScriptService.Server.Abilities.<Handler>`. Validated at registration time in `AbilityServer`.
	@field Config {[string]: any} -- Handler-specific configuration. Schema is defined by the handler module.
	@field Costs Costs -- Resources consumed atomically on activation. Use an empty table for no cost.
	@field Cooldown number -- Seconds before the ability (or its cooldown group) can be activated again.
	@field CooldownGroup string? -- nil = the ability has its own per-Kind cooldown. Otherwise abilities sharing a CooldownGroup share a single cooldown timer per player — useful for "primary attack" categories so a weapon swap doesn't reset the swing timer.
	@field Requirements {Requirement} -- Standard requirements composed via `Requirements.*`.
]=]
export type AbilityDef = {
	Kind: string,
	Handler: string,
	Config: { [string]: any },
	Costs: Costs,
	Cooldown: number,
	CooldownGroup: string?,
	Requirements: { Requirements.Requirement },
}

return {}
