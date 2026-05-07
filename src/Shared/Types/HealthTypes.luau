--!strict

--[=[
	@class HealthTypes
	Shared constants for Outworlder health. The character's `MaxHealth` is stored as a
	per-instance Roblox attribute on the character model so it replicates automatically
	and can vary per-entity in the future. Current `Health` is server-authoritative and
	replicated to the owning player via a Comm property.
]=]

local HealthTypes = {}

--[=[
	@prop DefaultMaxHealth number
	@within HealthTypes
	Fallback used when a character has no `MaxHealth` attribute set. Outworlders spawn
	with `Health == MaxHealth`.
]=]
HealthTypes.DefaultMaxHealth = 100

--[=[
	@prop HealthRegenPerSecond number
	@within HealthTypes
	Health recovered per second. Unlike stamina there is no post-damage delay; regen ticks
	every frame, just slowly.
]=]
HealthTypes.HealthRegenPerSecond = 1

--[=[
	@prop HealthReplicationInterval number
	@within HealthTypes
	Server-side throttle for replicating Health to the owning client (seconds between
	updates). Mirrors the stamina cadence.
]=]
HealthTypes.HealthReplicationInterval = 0.1

return HealthTypes
