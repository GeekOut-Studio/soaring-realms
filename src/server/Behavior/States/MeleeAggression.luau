--!strict

--[=[
	@class MeleeAggression
	State factory for melee combat. Pulls its target from the denizen's
	`CombatSession` (closest hostile alive member, picked sticky —
	re-evaluated only when the current target dies, leaves the session, or
	the session ends). Closes to `AttackRange`, faces the target, and asks
	`AbilityServer` to activate the configured `Ability` each tick once in
	range. Server-side cooldown gating on the ability throttles the actual
	swing rhythm; this state just keeps asking.

	Returns:
	- `OnTargetLost` when no hostile alive members remain in the session (or the session is gone).
	- `OnLeashed` when the current target's distance from `SpawnPosition` exceeds `LeashRange`.

	Writes `denizen.Target` as a projection of the currently-focused combatant
	for external reads (UI, debugging). Cleared in `Exit`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Targeting = require(ServerScriptService.Server.Behavior.Targeting)
local AbilityServer = require(ServerScriptService.Server.Servers.AbilityServer)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)

--[=[
	@interface Config
	@within MeleeAggression
	@field AttackRange number -- Stud distance at which the denizen stops to swing. Positioning concern; the actual hit range is the ability's, sourced from the denizen's `CombatStats.Range`.
	@field LeashRange number -- Stud distance from `SpawnPosition` past which the denizen disengages and returns.
	@field Ability string -- `AbilityDefs` key activated each tick once in range. Cooldown gating is server-side via `AbilityServer`.
	@field OnTargetLost string -- State to transition to when no hostile alive members remain.
	@field OnLeashed string -- State to transition to when the current target leaves `LeashRange` from spawn.
]=]
export type Config = {
	Kind: string,
	AttackRange: number,
	LeashRange: number,
	Ability: string,
	OnTargetLost: string,
	OnLeashed: string,
}

local function pickTarget(denizen: any): any?
	local session = denizen.CombatSession
	if session == nil then
		return nil
	end
	local pos = denizen.Instance:GetPivot().Position
	local closest = nil
	local closestDistSq = math.huge
	for member in session.Members do
		if member == denizen then
			continue
		end
		if member:GetHealth() <= 0 then
			continue
		end
		if not CombatTypes.IsHostile(denizen, member) then
			continue
		end
		local distSq = (member:GetCFrame().Position - pos).Magnitude ^ 2
		if distSq < closestDistSq then
			closest = member
			closestDistSq = distSq
		end
	end
	return closest
end

local function targetStillValid(denizen: any, target: any): boolean
	if target == nil then
		return false
	end
	if target:GetHealth() <= 0 then
		return false
	end
	local session = denizen.CombatSession
	if session == nil then
		return false
	end
	return session.Members[target] ~= nil
end

return function(config: Config)
	local currentTarget: any = nil

	return {
		Enter = function(denizen: any)
			currentTarget = pickTarget(denizen)
			denizen.Target = currentTarget
		end,
		Update = function(denizen: any, _dt: number): string?
			if not targetStillValid(denizen, currentTarget) then
				currentTarget = pickTarget(denizen)
				denizen.Target = currentTarget
			end

			if currentTarget == nil then
				return config.OnTargetLost
			end

			local pos = denizen.Instance:GetPivot().Position
			local targetPos = currentTarget:GetCFrame().Position

			if not Targeting.WithinCylinder(targetPos, denizen.SpawnPosition, config.LeashRange) then
				return config.OnLeashed
			end

			local distance = (targetPos - pos).Magnitude
			if distance > config.AttackRange then
				denizen:MoveTo(targetPos)
				denizen:FaceDirection(nil)
			else
				denizen:StopMoving()
				local toTarget = targetPos - pos
				if not toTarget:FuzzyEq(Vector3.zero) then
					denizen:FaceDirection(Vector3.new(toTarget.X, 0, toTarget.Z).Unit)
				end
				AbilityServer.Activate(denizen, config.Ability, nil)
			end
			return nil
		end,
		Exit = function(denizen: any)
			denizen:StopMoving()
			denizen:FaceDirection(nil)
			denizen.Target = nil
			currentTarget = nil
		end,
	}
end
