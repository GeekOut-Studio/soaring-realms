--!strict

--[=[
	@class BasicAttackWeaponMelee
	Ability handler for single-target melee attacks by player-style activators
	(activators that source combat stats from an equipped item slot). Reads the
	configured slot's `CombatStats` via `activator:GetCombatStats(config.Slot)`,
	plays the weapon's `AttackAnimation`, picks a target, faces the activator
	toward it, then applies a rolled damage value via `DamageServer`. Activation
	succeeds (animation plays, cooldown sets) even if no target is found — you
	swung, you committed.

	Target selection runs in two passes:

	1. **In combat** — the closest hostile alive member of the activator's
	   `CombatSession` within `Range`.
	2. **Out of combat** — `Targeting.NearestCombatantInWedge` scans the live
	   combatant registry for the closest hostile alive combatant within a
	   forward wedge (planar reach + total opening angle + vertical extrusion).
	   Lets a player run up and click an enemy to initiate combat; the damage
	   event triggers `CombatServer.Engage` automatically via the damage
	   pipeline.

	`OnWillCooldown` overrides the def's base cooldown with the equipped
	weapon's `CombatStats.Interval`, so swing rhythm follows the weapon.

	For denizen-style activators that source stats from their def rather than an
	equipped slot, see `DenizenMelee`. The two handlers duplicate the
	pick-closest-hostile + damage logic deliberately; the duplication is small
	and the alternative (a shared helper) would mostly obscure the per-handler
	shape.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageServer = require(ServerScriptService.Server.Servers.DamageServer)
local Targeting = require(ServerScriptService.Server.Targeting)
local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)

type AbilityActivator = AbilityTypes.AbilityActivator
type Combatant = CombatTypes.Combatant
type CombatStats = ItemStatsTypes.CombatStats

--[=[
	@interface Config
	@within BasicAttackWeaponMelee
	@field Slot EquipmentSlot -- Which equipment slot to read `CombatStats` from. Players use `"MainHandMelee"` for the primary attack; an off-hand or ranged variant ability would set its own slot here.
]=]
type Config = {
	Slot: EquipmentTypes.EquipmentSlot,
}

-- 90° total forward arc (±45° around the look vector). Tight enough that
-- the player has to roughly aim; loose enough to forgive a small miss.
local FORWARD_ARC_ANGLE = math.rad(90)
-- Total vertical extrusion of the swing-detection wedge, in studs (±half
-- around the activator's pivot). Generous because pivot Y varies between
-- rigs by several studs (e.g. an R15 player vs a short Denizen on the
-- same floor have ~5 studs of pivot disparity); ±6 here absorbs that plus
-- hops and small terrain differences. Targets on rooftops still excluded.
local WEDGE_HEIGHT = 8

-- The activator passed at the registry boundary is `AbilityActivator`. Each
-- function casts to `any` internally to call slot-based `GetCombatStats`, since
-- that method isn't part of the universal activator contract (e.g. Denizen,
-- which uses its own handler, doesn't have a slot-keyed `GetCombatStats`).
local function getCombatStats(activator: AbilityActivator, slot: EquipmentTypes.EquipmentSlot): CombatStats?
	return (activator :: any):GetCombatStats(slot)
end

local function pickFromCombatSession(activator: AbilityActivator, range: number): Combatant?
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
	Activate = function(activator: AbilityActivator, config: any, _context: any)
		local typedConfig = config :: Config
		local combatStats = getCombatStats(activator, typedConfig.Slot)
		if combatStats == nil then
			return
		end

		local faceTowardsDuration: number? = nil
		if combatStats.AttackAnimation ~= nil then
			local track = activator:AnimationPlay(combatStats.AttackAnimation, 0)
			if track.Length > 0 then
				faceTowardsDuration = track.Length
			end
		end
		local target = pickFromCombatSession(activator, combatStats.Range)
		if target == nil then
			target = Targeting.NearestCombatantInWedge(
				activator:GetCFrame(),
				combatStats.Range,
				WEDGE_HEIGHT,
				FORWARD_ARC_ANGLE,
				Targeting.HostileTo(activator :: any)
			)
		end
		if target == nil then
			return
		end

		activator:FaceTowards(target:GetRoot(), faceTowardsDuration)

		local rolled = combatStats.Power.Min + math.random() * (combatStats.Power.Max - combatStats.Power.Min)
		DamageServer.Damage({
			Amount = rolled,
			Type = combatStats.DamageType,
			Source = activator :: any,
			Target = target :: any,
		})
	end,

	OnWillCooldown = function(baseCooldown: number, activator: AbilityActivator, config: any, _context: any): number
		local typedConfig = config :: Config
		local combatStats = getCombatStats(activator, typedConfig.Slot)
		if combatStats == nil then
			return baseCooldown
		end
		return combatStats.Interval
	end,
}

return Handler
