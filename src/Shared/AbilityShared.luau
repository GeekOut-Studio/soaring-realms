--!strict

--[=[
	@class AbilityShared
	Pure-function validators shared by client (UI affordance) and server
	(authoritative gate) for ability activations.

	Requirement checking is intentionally out of scope here — the existing
	`Requirements` system already runs on both realms (`RequirementsServer`,
	`RequirementsClient`). Callers compose the requirement check with the
	affordability + cooldown check defined here.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)

type AbilityDef = AbilityTypes.AbilityDef

--[=[
	@interface ActivatorSnapshot
	@within AbilityShared
	@field Stamina number -- Activator's current stamina.
	@field GetItemCount (kind: string) -> number -- Returns total count of items of `kind` in the activator's inventory.
	@field GetCooldownExpiresAt (group: string) -> number -- Server-time at which the given cooldown group becomes ready. Return 0 (or any past time) if never set.
	@field Now number -- Current server-time reference for cooldown comparison. Both realms should use `Workspace:GetServerTimeNow()`.
]=]
export type ActivatorSnapshot = {
	Stamina: number,
	GetItemCount: (kind: string) -> number,
	GetCooldownExpiresAt: (group: string) -> number,
	Now: number,
}

local AbilityShared = {}

--[=[
	Returns the cooldown group for `def`. Defaults to `def.Kind` when the def has
	no explicit `CooldownGroup` — so each ability gets its own private timer
	unless deliberately bucketed.
	@within AbilityShared
	@param def AbilityDef
	@return string
]=]
function AbilityShared.GetCooldownGroup(def: AbilityDef): string
	return if def.CooldownGroup ~= nil then def.CooldownGroup else def.Kind
end

--[=[
	Checks that `def`'s costs and cooldown are satisfied by `snapshot`. Returns
	the first failure as `(false, message)`, or `(true, nil)` if every check
	passes. Requirements are NOT checked here.
	@within AbilityShared
	@param snapshot ActivatorSnapshot
	@param def AbilityDef
	@return (boolean, string?)
]=]
function AbilityShared.IsAffordableAndReady(snapshot: ActivatorSnapshot, def: AbilityDef): (boolean, string?)
	local group = AbilityShared.GetCooldownGroup(def)
	if snapshot.Now < snapshot.GetCooldownExpiresAt(group) then
		return false, "Ability is on cooldown."
	end
	if def.Costs.Stamina ~= nil and snapshot.Stamina < def.Costs.Stamina then
		return false, "Not enough stamina."
	end
	if def.Costs.Items ~= nil then
		for kind, count in def.Costs.Items do
			if snapshot.GetItemCount(kind) < count then
				return false, "Missing required items."
			end
		end
	end
	return true, nil
end

return AbilityShared
