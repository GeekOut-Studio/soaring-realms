--!strict

--[=[
	@class AbilityServer
	Authoritative ability activation pipeline. Looks up the def, runs the
	standard validator (Requirements + Costs + Cooldown), atomically deducts
	costs, dispatches to the handler module, sets the cooldown, and (for
	player activators only) replicates the updated cooldown table.

	Accepts any `AbilityActivator` — players (via the Comm-bound entry that
	resolves Player → Outworlder) and denizens (via direct in-process calls
	from their behavior states) go through the same pipeline.

	Cooldown state is held in-memory keyed by activator (does not persist).
	Players unloading and denizens stopping must explicitly drop their state
	through `ResetCooldowns`.
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
local DenizenMelee = require(ServerScriptService.Server.Abilities.DenizenMelee)
local BasicAttackWeaponMelee = require(ServerScriptService.Server.Abilities.BasicAttackWeaponMelee)
local AbilityDefs = require(ReplicatedStorage.Shared.Defs.AbilityDefs)
local AbilityShared = require(ReplicatedStorage.Shared.AbilityShared)
local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)

type AbilityActivator = AbilityTypes.AbilityActivator

local HANDLERS: { [string]: AbilityTypes.AbilityHandler } = {
	BasicAttackWeaponMelee = BasicAttackWeaponMelee,
	DenizenMelee = DenizenMelee,
}

local AbilityServer = {}

local cooldownsByActivator: { [any]: { [string]: number } } = {}
local cooldownsProperty

local function getCooldowns(activator: any): { [string]: number }
	local existing = cooldownsByActivator[activator]
	if existing == nil then
		existing = {}
		cooldownsByActivator[activator] = existing
	end
	return existing
end

-- Returns the player whose cooldowns should be replicated to, or nil for
-- non-player activators (whose cooldowns aren't replicated at all).
local function getOwningPlayer(activator: any): Player?
	return activator.Player
end

--[=[
	Activates the ability identified by `abilityKind` for `activator`. Returns
	`(true, nil)` on success, or `(false, message)` on rejection. All gating
	runs server-side; the client may pre-validate via `AbilityShared` for UI
	affordance but the server is the source of truth.

	Order of checks: requirements (player only), then affordability + cooldown,
	then atomic cost deduction, then dispatch to the handler runtime, then
	cooldown bump (via `OnWillCooldown` if the handler provides one).

	Costs are only meaningfully deductible from player activators today
	(Stamina + Inventory). Denizens currently have no Costs configured; the
	pipeline still walks through the checks (which will pass on empty Costs).
	@within AbilityServer
	@param activator AbilityActivator
	@param abilityKind string
	@param context any? -- Per-handler activation context. Pass `nil` when the ability's `Targeting` is `"None"`.
	@return (boolean, string?)
]=]
function AbilityServer.Activate(activator: AbilityActivator, abilityKind: string, context: any?): (boolean, string?)
	local def = AbilityDefs[abilityKind]
	if def == nil then
		return false, `Unknown ability "{abilityKind}".`
	end

	-- Requirements use the player-data snapshot; only meaningful for players.
	local player = getOwningPlayer(activator)
	if player ~= nil then
		local reqOk, reqMsg = RequirementsServer.CheckForPlayer(player, def.Requirements)
		if not reqOk then
			return false, reqMsg
		end
	end

	-- Early cooldown short-circuit. Behavior states (e.g. `MeleeAggression`)
	-- spam-call `Activate` every heartbeat once in range and rely on the
	-- server to throttle. Checking cooldown before constructing the
	-- affordability snapshot avoids per-tick closure allocations for the
	-- vastly more common "still on cooldown" case.
	local cooldowns = getCooldowns(activator)
	local now = Workspace:GetServerTimeNow()
	local group = AbilityShared.GetCooldownGroup(def)
	if now < (cooldowns[group] or 0) then
		return false, "Ability is on cooldown."
	end

	local snapshot: AbilityShared.ActivatorSnapshot = {
		Stamina = if player ~= nil then (activator :: any).Stamina else 100,
		GetItemCount = function(kind)
			if player == nil then
				return 0
			end
			return InventoryServer.GetItemCount(player, kind)
		end,
		GetCooldownExpiresAt = function(g)
			return cooldowns[g] or 0
		end,
		Now = now,
	}
	local affOk, affMsg = AbilityShared.IsAffordableAndReady(snapshot, def)
	if not affOk then
		return false, affMsg
	end

	-- Cost deduction. Player-only today (Stamina lives on Outworlder; items
	-- live in player inventory). Denizen activations are assumed to have
	-- empty Costs, validated by the affordability check above.
	if player ~= nil then
		if def.Costs.Stamina ~= nil then
			(activator :: any).Stamina = math.max(0, (activator :: any).Stamina - def.Costs.Stamina)
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
	end

	local handler = HANDLERS[def.Handler]
	assert(handler ~= nil, `AbilityServer.Activate: no handler registered for "{def.Handler}"`)

	handler.Activate(activator, def.Config, context)

	-- Cooldown is computed AFTER `Activate` so the handler may legally mutate
	-- activator state (e.g. swap weapons, consume buffs) and have those changes
	-- reflected in the new cooldown duration. Re-entry between `Activate`'s
	-- start and this assignment is impossible because no handler yields.
	local cooldown = def.Cooldown
	if handler.OnWillCooldown ~= nil then
		cooldown = handler.OnWillCooldown(cooldown, activator, def.Config, context)
	end

	cooldowns[group] = Workspace:GetServerTimeNow() + cooldown
	if player ~= nil then
		cooldownsProperty:SetFor(player, cooldowns)
	end

	return true, nil
end

--[=[
	Drops `activator`'s cooldown state. Call from the activator's teardown
	(`Players.PlayerRemoving` for players, `Denizen:Stop` for denizens) so the
	in-memory table doesn't accumulate dead references.
	@within AbilityServer
	@param activator AbilityActivator
]=]
function AbilityServer.ResetCooldowns(activator: AbilityActivator)
	cooldownsByActivator[activator] = nil
end

function AbilityServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Ability")
	cooldownsProperty = serverComm:CreateProperty("Cooldowns", {})

	serverComm:BindFunction("Activate", function(player: Player, abilityKind: any)
		if not t.string(abilityKind) then
			return false, "Bad ability kind."
		end
		local character = player.Character
		if character == nil then
			return false, "Character not ready."
		end
		local outworlder = Outworlder:FromInstance(character)
		if outworlder == nil then
			return false, "Character not ready."
		end

		local success, reason = AbilityServer.Activate(outworlder, abilityKind, nil)
		return success, reason or ""
	end)

	local function pushInitialCooldowns(player: Player)
		cooldownsProperty:SetFor(player, {})
	end
	Players.PlayerAdded:Connect(pushInitialCooldowns)
	for _, player in Players:GetPlayers() do
		task.spawn(pushInitialCooldowns, player)
	end

	-- Observe Outworlder teardown via the component framework rather than
	-- `Players.PlayerRemoving`. `player.Character` is often already `nil` by
	-- the time `PlayerRemoving` fires, which would leak the Outworlder's
	-- cooldown entry; `Component.Stopped` carries the instance directly and
	-- always fires when the tag goes away. Denizen has the same need but goes
	-- through its own `Stop()` call (the require cycle here blocks an
	-- equivalent external hook).
	Outworlder.Stopped:Connect(function(outworlder)
		AbilityServer.ResetCooldowns(outworlder)
	end)
end

return AbilityServer
