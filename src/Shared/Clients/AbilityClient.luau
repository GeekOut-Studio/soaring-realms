--[=[
	@class AbilityClient
	@client
	Client-side interface for the local player's abilities. Owns the only
	reference to the server-side `Ability` Comm on the client and exposes a
	thin wrapper around it: `Activate` for player-initiated requests, and
	cooldown queries for UI affordance (greyed icons, cooldown rings).

	The `Cooldowns` Comm property mirrors a `{[group]: expiresAt}` table from
	`AbilityServer`. Both realms key off `Workspace:GetServerTimeNow()`, so
	`expiresAt - GetServerTimeNow()` produces the remaining cooldown directly.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)

local AbilityClient = {}

local activateFunction
local cooldownsProperty

function AbilityClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Ability")
	activateFunction = clientComm:GetFunction("Activate")
	cooldownsProperty = clientComm:GetProperty("Cooldowns")
end

--[=[
	Asks the server to activate `abilityKind` for the local player. Server is
	authoritative for requirements / costs / cooldown; this is fire-and-forget
	from the client's perspective.
	@within AbilityClient
	@param abilityKind string
	@return (boolean, string) -- ok, message ("" on success).
]=]
function AbilityClient.Activate(abilityKind: string): (boolean, string)
	return activateFunction(abilityKind)
end

--[=[
	Returns the server-time at which `group`'s cooldown expires. `0` if the
	group has never been put on cooldown (or has been since reset).
	@within AbilityClient
	@param group string
	@return number
]=]
function AbilityClient.GetCooldownExpiresAt(group: string): number
	local cooldowns = cooldownsProperty:Get() :: { [string]: number }
	return cooldowns[group] or 0
end

--[=[
	Returns the seconds remaining on `group`'s cooldown, clamped at 0. Useful
	directly as a "is this on cooldown" predicate (`> 0`) and as input for a
	cooldown ring's progress fraction.
	@within AbilityClient
	@param group string
	@return number
]=]
function AbilityClient.GetCooldownRemaining(group: string): number
	return math.max(0, AbilityClient.GetCooldownExpiresAt(group) - Workspace:GetServerTimeNow())
end

return AbilityClient
