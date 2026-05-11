--!strict

--[=[
	@class DenizenMelee
	Ability handler for single-target melee attacks by denizen-style activators
	(activators whose `CombatStats` live on their static def rather than in an
	equipped slot). Reads `activator.Def.CombatStats`, plays the def's
	`AttackAnimation`, then scans the activator's `CombatSession` for the
	closest hostile alive combatant within `Range` and applies a rolled damage
	value via `DamageServer`. Activation succeeds (animation plays, cooldown
	sets) even if no target is in range.

	`OnWillCooldown` overrides the def's base cooldown with the denizen's
	`CombatStats.Interval`, so swing rhythm follows the denizen def.

	For player-style activators that read combat stats from an equipped slot,
	see `BasicAttackWeaponMelee`. The two handlers duplicate the pick-closest-hostile
	+ damage logic deliberately; the duplication is small and the alternative
	(a shared helper) would mostly obscure the per-handler shape.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageServer = require(ServerScriptService.Server.Servers.DamageServer)
local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)

type AbilityActivator = AbilityTypes.AbilityActivator
type Combatant = CombatTypes.Combatant
type CombatStats = ItemStatsTypes.CombatStats

-- The activator at the registry boundary is `AbilityActivator`. This handler
-- expects a `Denizen`: it reads `activator.Def.CombatStats` directly via a
-- cast, since the universal activator interface doesn't expose `.Def`.
local function getCombatStats(activator: AbilityActivator): CombatStats?
	return (activator :: any).Def.CombatStats
end

local function pickClosestHostile(activator: AbilityActivator, range: number): Combatant?
	local session = activator.CombatSession
	if session == nil then
		return nil
	end
	local pos = activator:GetCFrame().Position
	local rangeSq = range * range
	local best: Combatant? = nil
	local bestDistSq = math.huge
	for member in session.Members do
		if (member :: any) == activator then
			continue
		end
		if member:GetHealth() <= 0 then
			continue
		end
		if not CombatTypes.IsHostile(activator :: any, member) then
			continue
		end
		local distSq = (member:GetCFrame().Position - pos).Magnitude ^ 2
		if distSq <= rangeSq and distSq < bestDistSq then
			best = member
			bestDistSq = distSq
		end
	end
	return best
end

local Handler: AbilityTypes.AbilityHandler = {
	Activate = function(activator: AbilityActivator, _config: any, _context: any)
		local combatStats = getCombatStats(activator)
		if combatStats == nil then
			return
		end

		if combatStats.AttackAnimation ~= nil then
			activator:AnimationPlay(combatStats.AttackAnimation)
		end

		local target = pickClosestHostile(activator, combatStats.Range)
		if target == nil then
			return
		end

		local rolled = combatStats.Power.Min + math.random() * (combatStats.Power.Max - combatStats.Power.Min)
		DamageServer.Damage({
			Amount = rolled,
			Type = combatStats.DamageType,
			Source = activator :: any,
			Target = target :: any,
		})
	end,

	OnWillCooldown = function(baseCooldown: number, activator: AbilityActivator, _config: any, _context: any): number
		local combatStats = getCombatStats(activator)
		if combatStats == nil then
			return baseCooldown
		end
		return combatStats.Interval
	end,
}

return Handler
