--!strict

--[=[
	@class MeleeAggression
	State factory for melee combat. Closes to `AttackRange` of `denizen.Target`, faces it,
	and applies `AttackDamage` of `AttackKind` damage every `AttackCooldown` seconds via
	`DamageServer`. Returns `"Idle"` when the target is gone or dead, `"Returning"` if the
	target leaves `LeashRange`.

	The damage is applied directly here (rather than through an Abilities system) until that
	system lands; see the plan's "Cooldown bookkeeping for abilities" open decision.
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
	@field OnTargetLost string -- State to transition to when the target is gone or dead.
	@field OnLeashed string -- State to transition to when the target leaves `LeashRange` from spawn.
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

local function isDead(target: any): boolean
	if target.GetHealth == nil then
		return true
	end
	return target:GetHealth() <= 0
end

return function(config: Config)
	local attackTimer = 0

	return {
		Enter = function(_denizen: any)
			attackTimer = 0
		end,
		Update = function(denizen: any, dt: number): string?
			local target = denizen.Target
			if target == nil or isDead(target) then
				denizen.Target = nil
				return config.OnTargetLost
			end

			local pos = denizen.Instance:GetPivot().Position
			local targetPos = target.Instance:GetPivot().Position

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
						Target = target,
					})
				end
			end
			return nil
		end,
		Exit = function(denizen: any)
			denizen:StopMoving()
			denizen:FaceDirection(nil)
		end,
	}
end
