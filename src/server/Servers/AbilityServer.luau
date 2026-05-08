--!strict

--[=[
	@class AbilityServer
	Authoritative ability activation pipeline for players. Looks up the def, runs
	the standard validator (Requirements + Costs + Cooldown), atomically deducts
	costs, dispatches to the handler module, sets the cooldown, and replicates
	the updated cooldown table to the activating player.

	Cooldown state is held in-memory per player (does not persist across sessions).
	Players unloading is treated as state reset.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local t = require(ReplicatedStorage.Packages.t)

local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local RequirementsServer = require(ServerScriptService.Server.Servers.RequirementsServer)
local Outworlder = require(ServerScriptService.Server.Components.Outworlder)
local SingleTargetMelee = require(ServerScriptService.Server.Abilities.SingleTargetMelee)
local AbilityDefs = require(ReplicatedStorage.Shared.Defs.AbilityDefs)
local AbilityShared = require(ReplicatedStorage.Shared.AbilityShared)

type Handler = {
	Activate: (any, any) -> (),
	OnWillCooldown: ((baseCooldown: number, activator: any, config: any) -> number)?,
}

local HANDLERS: { [string]: Handler } = {
	SingleTargetMelee = SingleTargetMelee,
}

local AbilityServer = {}

local cooldownsByPlayer: { [Player]: { [string]: number } } = {}
local cooldownsProperty

local function getCooldowns(player: Player): { [string]: number }
	local existing = cooldownsByPlayer[player]
	if existing == nil then
		existing = {}
		cooldownsByPlayer[player] = existing
	end
	return existing
end

--[=[
	Activates the ability identified by `abilityKind` for `player`. Returns
	`(true, nil)` on success, or `(false, message)` on rejection. All gating
	runs server-side; the client may pre-validate via `AbilityShared` for UI
	affordance but the server is the source of truth.

	Order of checks: requirements, then affordability + cooldown, then atomic
	cost deduction, then cooldown bump, then dispatch to the handler runtime.
	Cooldown is set BEFORE the runtime executes so re-entrant activations
	cannot double-fire.
	@within AbilityServer
	@param player Player
	@param abilityKind string
	@return (boolean, string?)
]=]
function AbilityServer.Activate(player: Player, abilityKind: string): (boolean, string?)
	local def = AbilityDefs[abilityKind]
	if def == nil then
		return false, `Unknown ability "{abilityKind}".`
	end

	local reqOk, reqMsg = RequirementsServer.CheckForPlayer(player, def.Requirements)
	if not reqOk then
		return false, reqMsg
	end

	local character = player.Character
	if character == nil then
		return false, "Character not ready."
	end
	local outworlder = Outworlder:FromInstance(character)
	if outworlder == nil then
		return false, "Character not ready."
	end

	local cooldowns = getCooldowns(player)
	local snapshot: AbilityShared.ActivatorSnapshot = {
		Stamina = outworlder.Stamina,
		GetItemCount = function(kind)
			return InventoryServer.GetItemCount(player, kind)
		end,
		GetCooldownExpiresAt = function(group)
			return cooldowns[group] or 0
		end,
		Now = Workspace:GetServerTimeNow(),
	}
	local affOk, affMsg = AbilityShared.IsAffordableAndReady(snapshot, def)
	if not affOk then
		return false, affMsg
	end

	-- Cost deduction. Both deductions are guaranteed to succeed by the
	-- affordability check above and the absence of yields between check and
	-- here (Roblox single-threaded per request). True cross-store atomicity
	-- (Stamina lives outside DataServer) is a future concern.
	if def.Costs.Stamina ~= nil then
		outworlder.Stamina = math.max(0, outworlder.Stamina - def.Costs.Stamina)
	end
	if def.Costs.Items ~= nil then
		for kind, count in def.Costs.Items do
			local removed = InventoryServer.RemoveItemByKind(player, kind, count)
			assert(
				removed,
				`AbilityServer.Activate: item-cost deduction failed for "{kind}" after affordability check passed`
			)
		end
	end

	local handler = HANDLERS[def.Handler]
	assert(handler ~= nil, `AbilityServer.Activate: no handler registered for "{def.Handler}"`)

	local cooldown = def.Cooldown
	if handler.OnWillCooldown ~= nil then
		cooldown = handler.OnWillCooldown(cooldown, outworlder, def.Config)
	end

	local group = AbilityShared.GetCooldownGroup(def)
	cooldowns[group] = Workspace:GetServerTimeNow() + cooldown
	cooldownsProperty:SetFor(player, cooldowns)

	handler.Activate(outworlder, def.Config)

	return true, nil
end

function AbilityServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Ability")
	cooldownsProperty = serverComm:CreateProperty("Cooldowns", {})

	serverComm:BindFunction("Activate", function(player: Player, abilityKind: any)
		if not t.string(abilityKind) then
			return false, "Bad ability kind."
		end

		local success, reason = AbilityServer.Activate(player, abilityKind)
		return success, reason or ""
	end)

	Players.PlayerAdded:Connect(function(player)
		cooldownsProperty:SetFor(player, getCooldowns(player))
	end)
	for _, player in Players:GetPlayers() do
		cooldownsProperty:SetFor(player, getCooldowns(player))
	end

	Players.PlayerRemoving:Connect(function(player)
		cooldownsByPlayer[player] = nil
	end)
end

return AbilityServer
