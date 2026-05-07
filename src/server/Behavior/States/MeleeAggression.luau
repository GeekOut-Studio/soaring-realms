--!strict

--[=[
	@class MeleeAggression
	State factory for melee combat. Pulls its target from the denizen's `CombatSession`
	(closest hostile alive member, picked sticky — re-evaluated only when the current target
	dies, leaves the session, or the session ends). Closes to `AttackRange`, faces the
	target, and applies `AttackDamage` of `AttackKind` damage every `AttackCooldown` seconds
	via `DamageServer`.

	Returns:
	- `OnTargetLost` when no hostile alive members remain in the session (or the session is gone).
	- `OnLeashed` when the current target's distance from `SpawnPosition` exceeds `LeashRange`.

	Damage is dealt directly here rather than via an Abilities system; revisit when that
	system lands.

	Writes `denizen.Target` as a projection of the currently-focused combatant for external
	reads (UI, debugging). Cleared in `Exit`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageServer = require(ServerScriptService.Server.Servers.DamageServer)
local DamageTypes = require(ReplicatedStorage.Shared.Types.DamageTypes)

type DamageKind = DamageTypes.DamageKind

--[=[
	@interface Config
	@within MeleeAggression
	@field AttackRange number -- Stud distance at which the denizen stops to swing.
	@field LeashRange number -- Stud distance from `SpawnPosition` past which the denizen disengages and returns.
	@field AttackCooldown number -- Seconds between successive hits.
	@field AttackDamage number
	@field AttackKind DamageKind
	@field AttackAnimation string? -- Optional `AnimationDefs` key played on each swing.
	@field OnTargetLost string -- State to transition to when no hostile alive members remain.
	@field OnLeashed string -- State to transition to when the current target leaves `LeashRange` from spawn.
]=]
export type Config = {
	Kind: string,
	AttackRange: number,
	LeashRange: number,
	AttackCooldown: number,
	AttackDamage: number,
	AttackKind: DamageKind,
	AttackAnimation: string?,
	OnTargetLost: string,
	OnLeashed: string,
}

local function isHostile(a: any, b: any): boolean
	local ta, tb = a:GetTeam(), b:GetTeam()
	return ta == nil or tb == nil or ta ~= tb
end

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
		if not isHostile(denizen, member) then
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
	local attackTimer = 0
	local currentTarget: any = nil

	return {
		Enter = function(denizen: any)
			attackTimer = 0
			currentTarget = pickTarget(denizen)
			denizen.Target = currentTarget
		end,
		Update = function(denizen: any, dt: number): string?
			if not targetStillValid(denizen, currentTarget) then
				currentTarget = pickTarget(denizen)
				denizen.Target = currentTarget
			end

			if currentTarget == nil then
				return config.OnTargetLost
			end

			local pos = denizen.Instance:GetPivot().Position
			local targetPos = currentTarget:GetCFrame().Position

			if (targetPos - denizen.SpawnPosition).Magnitude > config.LeashRange then
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
				attackTimer -= dt
				if attackTimer <= 0 then
					attackTimer = config.AttackCooldown
					if config.AttackAnimation ~= nil then
						denizen:AnimationPlay(config.AttackAnimation)
					end
					DamageServer.Damage({
						Amount = config.AttackDamage,
						Kind = config.AttackKind,
						Source = denizen,
						Target = currentTarget,
					})
				end
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
