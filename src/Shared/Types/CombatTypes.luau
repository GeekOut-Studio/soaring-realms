--!strict

--[=[
	@class CombatTypes
	Shared types for the combat-session system. The `Combatant` interface is duck-typed —
	any object with the methods below can be added to a `CombatSession`. Both `Outworlder`
	and `Denizen` satisfy it. The `CombatSession` shape is exposed here so consumers
	(behavior states, UI, debug tooling) can read members without importing the server-only
	`CombatServer` module.
]=]

--[=[
	@interface Combatant
	@within CombatTypes
	@field GetTeam (Combatant) -> string? -- Returns the combatant's team. `nil` means hostile to everyone.
	@field GetCFrame (Combatant) -> CFrame -- Position + facing. Used for range checks and any direction-dependent mechanics (backstabs, line-of-sight).
	@field GetHealth (Combatant) -> number -- Reused from `DamageTarget`; `<= 0` means dead.
	@field CombatSession CombatSession? -- Back-reference written by `CombatServer`. `nil` when out of combat.
]=]
export type Combatant = {
	GetTeam: (Combatant) -> string?,
	GetCFrame: (Combatant) -> CFrame,
	GetHealth: (Combatant) -> number,
	CombatSession: CombatSession?,
}

--[=[
	@interface CombatSession
	@within CombatTypes
	@field Members {[Combatant]: number} -- Combatant → `os.clock()` of last involvement (the per-combatant CombatTimer).
]=]
export type CombatSession = {
	Members: { [Combatant]: number },
}

local CombatTypes = {}

--[=[
	Returns whether two combatants are considered hostile to each other. The rule:
	if either combatant's team is `nil` (hostile to all), or their teams differ,
	they are hostile. Same-team combatants are never hostile.
	@within CombatTypes
	@param a Combatant
	@param b Combatant
	@return boolean
]=]
function CombatTypes.IsHostile(a: Combatant, b: Combatant): boolean
	local ta, tb = a:GetTeam(), b:GetTeam()
	return ta == nil or tb == nil or ta ~= tb
end

return CombatTypes
