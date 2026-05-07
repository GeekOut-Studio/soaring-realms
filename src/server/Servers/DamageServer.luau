--!strict

--[=[
	@class DamageServer
	@server
	Centralized damage pipeline. Every damage event in the game flows through
	`DamageServer.Damage`, which threads the immutable `Damage` record through the
	source-side and target-side `OnWill*Damage` hooks, applies the resulting amount to the
	target's health, then runs the `OnDid*Damage` hooks for post-apply processing.

	Pipeline order (each step can transform the `Damage`):
	1. `Source:OnWillDealDamage(damage)` — source-side modifiers (crits, weapon enchants, …)
	2. `Target:OnWillTakeDamage(damage)` — target-side modifiers (armor, resistances, shields, …)
	3. Apply: `Target:SetHealth(max(0, Target:GetHealth() - damage.Amount))`
	4. `Source:OnDidDealDamage(damage)` — source-side post-apply (e.g. lifesteal, telemetry)
	5. `Target:OnDidTakeDamage(damage)` — target-side post-apply (e.g. on-hit effects)

	Hooks are pure transforms: they return a (possibly-new) frozen `Damage` and must not
	yield. Cascading damage (thorns, retaliate) should call `DamageServer.Damage` again
	rather than chaining within a single pipeline run.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageTypes = require(ReplicatedStorage.Shared.Types.DamageTypes)

type Damage = DamageTypes.Damage

local DamageServer = {}

local EMPTY_TAGS = table.freeze({}) :: { [string]: true }

--[=[
	Runs `damage` through the full pipeline and applies the resulting amount to the target.
	@within DamageServer
	@server
	@param damage Damage
]=]
function DamageServer.Damage(damage: Damage)
	local normalized = table.clone(damage)
	if normalized.Tags == nil then
		normalized.Tags = EMPTY_TAGS
	end
	local current = table.freeze(normalized) :: Damage

	if current.Source ~= nil then
		local onWillDeal = current.Source.OnWillDealDamage
		if onWillDeal ~= nil then
			current = onWillDeal(current.Source, current)
		end
	end

	local onWillTake = current.Target.OnWillTakeDamage
	if onWillTake ~= nil then
		current = onWillTake(current.Target, current)
	end

	local health = current.Target:GetHealth()
	current.Target:SetHealth(math.max(0, health - current.Amount))

	if current.Source ~= nil then
		local onDidDeal = current.Source.OnDidDealDamage
		if onDidDeal ~= nil then
			current = onDidDeal(current.Source, current)
		end
	end

	local onDidTake = current.Target.OnDidTakeDamage
	if onDidTake ~= nil then
		current = onDidTake(current.Target, current)
	end
end

return DamageServer
