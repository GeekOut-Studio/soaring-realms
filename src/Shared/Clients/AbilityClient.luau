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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)

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

	`context` is the per-handler activation payload. Callers populate
	handler-specific fields (e.g. a `GroundPoint` for a place-instance
	ability); they do *not* need to attach the player's CFrame manually — this
	function auto-attaches `ActivatorCFrame = LocalPlayer.Character.PrimaryPart.CFrame`
	when present, which the server hands to `Outworlder:SetClientCFrame` to
	keep `outworlder:GetCFrame()` returning the ahead-of-replication position
	for the next freshness window.
	@within AbilityClient
	@param abilityKind string
	@param context any?
	@return (boolean, string) -- ok, message ("" on success).
]=]
function AbilityClient.Activate(abilityKind: string, context: any?): (boolean, string)
	local outgoing = context
	local character = Players.LocalPlayer.Character
	local primary = if character ~= nil then character.PrimaryPart else nil
	if primary ~= nil then
		if outgoing == nil then
			outgoing = { ActivatorCFrame = primary.CFrame }
		elseif outgoing.ActivatorCFrame == nil then
			outgoing = table.clone(outgoing)
			outgoing.ActivatorCFrame = primary.CFrame
		end
	end
	return activateFunction(abilityKind, outgoing)
end

--[=[
	Observes changes to the local player's cooldown table.

	`callback` is called immediately with the current value and again on every
	change. It may return a cleanup function that runs before the next
	invocation and on disconnect.
	@within AbilityClient
	@param callback (cooldowns: {[string]: number}) -> (() -> ())?
	@return () -> () -- Disconnects the observer.
]=]
function AbilityClient.ObserveCooldowns(callback: (cooldowns: { [string]: number }) -> (() -> ())?)
	return Observing.observeCommProperty(cooldownsProperty, callback)
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
