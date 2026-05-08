--!strict

--[=[
	@class SingleTargetMelee
	Ability handler for single-target melee attacks. Reads the activator's
	`MainHandMelee` weapon stats (`Power`, `Range`, `DamageType`, `Interval`)
	via `activator:GetCombatStats("MainHandMelee")`, plays the configured
	swing animation, then scans the activator's `CombatSession` for the
	closest hostile alive combatant within `Range` and applies a rolled
	damage value via `DamageServer`. Activation succeeds (animation plays,
	cooldown sets) even if no target is in range — you swung, you committed.
	Out-of-combat or no-weapon-equipped activations no-op on the damage step
	but still play the animation.

	`OnWillCooldown` overrides the def's base cooldown with the equipped
	weapon's `CombatStats.Interval`, so swing rhythm follows whatever weapon
	the wielder has equipped at the moment of activation rather than being
	baked into the ability def.

	Requires the activator to expose `GetCombatStats(slot)`, `GetCFrame`,
	`AnimationPlay`, and `CombatSession` (i.e. an `Outworlder`). Denizens
	that want this handler will need to provide their own `GetCombatStats`
	projection when the ability system absorbs their attacks.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageServer = require(ServerScriptService.Server.Servers.DamageServer)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)

type Combatant = CombatTypes.Combatant

--[=[
	@interface Config
	@within SingleTargetMelee
	@field Animation string -- `AnimationDefs` key played by the activator on each attack.
]=]
type Config = {
	Animation: string,
}

local function pickClosestHostile(activator: any, range: number): Combatant?
	local session = activator.CombatSession
	if session == nil then
		return nil
	end
	local pos = activator:GetCFrame().Position
	local rangeSq = range * range
	local best: Combatant? = nil
	local bestDistSq = math.huge
	for member in session.Members do
		if member == activator then
			continue
		end
		if member:GetHealth() <= 0 then
			continue
		end
		if not CombatTypes.IsHostile(activator, member) then
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

return {
	Activate = function(activator: any, config: Config)
		activator:AnimationPlay(config.Animation)

		local combatStats = activator:GetCombatStats("MainHandMelee")
		if combatStats == nil then
			return
		end

		local target = pickClosestHostile(activator, combatStats.Range)
		if target == nil then
			return
		end

		local rolled = combatStats.Power.Min + math.random() * (combatStats.Power.Max - combatStats.Power.Min)
		DamageServer.Damage({
			Amount = rolled,
			Type = combatStats.DamageType,
			Source = activator,
			Target = target :: any,
		})
	end,

	OnWillCooldown = function(baseCooldown: number, activator: any, _config: Config): number
		local combatStats = activator:GetCombatStats("MainHandMelee")
		if combatStats == nil then
			return baseCooldown
		end
		return combatStats.Interval
	end,
}
