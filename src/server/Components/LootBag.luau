--!strict

--[=[
	@class LootBag
	Server component for the `LootBag` tag. The spatial + Comm view of a
	loot pile; the loot data itself lives in `LootServer` for the bag's
	whole lifetime (see `LootServer.GetBagLoot` / `ClaimOne` / `ClaimAll`
	/ `DiscardBag`). Spawned by `LootServer.SpawnBag`; never authored.

	On `Construct`, reads the bag's loot map from `LootServer` and seeds
	`LootProperty:SetFor(player, loot)` for each eligible player. Other
	players see the property's default value (`nil`) and `LootBagClient`
	renders nothing for them.

	Exposes two server-bound functions:
	- `LootOne(player, index)` — claim a specific item by index.
	- `LootAll(player)` — claim everything in the player's pile.

	After each successful claim, re-pushes the current per-player array
	(or `nil` when emptied) so the client UI reflects the new state.

	`Stop` is responsible for calling `LootServer.DiscardBag` so the
	server-side map doesn't accumulate dead-instance entries.

	Despawns automatically when every eligible player has looted (or
	forfeited) OR when `LOOT_BAG_LIFETIME` seconds have elapsed since
	spawn, whichever comes first.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local LootServer = require(ServerScriptService.Server.Servers.LootServer)

local LOOT_BAG_LIFETIME = 300
local MAX_LOOT_DISTANCE = 8

local LootBag = Component.new({
	Tag = "LootBag",
	Ancestors = { Workspace },
})

--[=[
	@prop LootProperty any
	@within LootBag
	Per-player `RemoteProperty`. Each eligible player sees their own
	`PlayerLoot`; everyone else sees `nil`.
]=]

function LootBag:Construct()
	self.Trove = Trove.new()

	self.Comm = Comm.ServerComm.new(self.Instance, "LootBag")
	self.Trove:Add(self.Comm)
	self.LootProperty = self.Comm:CreateProperty("Loot", nil)
	self.Comm:BindFunction("LootOne", function(player: Player, index: any, targetSlot: any)
		if not t.integer(index) then
			return false
		end
		if targetSlot ~= nil and not t.string(targetSlot) then
			return false
		end
		return self:HandleLootOne(player, index, targetSlot)
	end)
	self.Comm:BindFunction("LootAll", function(player: Player)
		return self:HandleLootAll(player)
	end)

	local loot = LootServer.GetBagLoot(self.Instance)
	if loot ~= nil then
		for player, lootArr in loot do
			self.LootProperty:SetFor(player, lootArr)
		end
	end
end

function LootBag:Start()
	if LootServer.IsBagEmpty(self.Instance) then
		self.Instance:Destroy()
		return
	end
	self.Trove:Add(task.delay(LOOT_BAG_LIFETIME, function()
		self.Instance:Destroy()
	end))
end

function LootBag:Stop()
	LootServer.DiscardBag(self.Instance)
	self.Trove:Destroy()
end

--[=[
	Server-bound `LootOne` handler. Validates proximity, delegates the
	authoritative claim to `LootServer.ClaimOne` (forwarding the optional
	`targetSlot` preference from drag-to-specific-slot drops), then
	re-pushes the per-player loot view (or `nil` when emptied). Destroys
	the bag when no player has loot left.
	@within LootBag
	@param player Player
	@param index number
	@param targetSlot string?
	@return boolean
]=]
function LootBag:HandleLootOne(player: Player, index: number, targetSlot: string?): boolean
	if not self:IsPlayerInRange(player) then
		return false
	end

	if not LootServer.ClaimOne(self.Instance, player, index, targetSlot) then
		return false
	end

	self:ReplicateLootForPlayer(player)
	if LootServer.IsBagEmpty(self.Instance) then
		self.Instance:Destroy()
	end
	return true
end

--[=[
	Server-bound `LootAll` handler. Validates proximity, delegates to
	`LootServer.ClaimAll`, then re-pushes the per-player loot view.
	@within LootBag
	@param player Player
	@return boolean
]=]
function LootBag:HandleLootAll(player: Player): boolean
	if not self:IsPlayerInRange(player) then
		return false
	end

	if not LootServer.ClaimAll(self.Instance, player) then
		return false
	end

	self:ReplicateLootForPlayer(player)
	if LootServer.IsBagEmpty(self.Instance) then
		self.Instance:Destroy()
	end
	return true
end

--[=[
	Re-pushes `player`'s current pile via `LootProperty:SetFor`. Sends
	`nil` when their pile is empty so the client can hide the UI.
	@within LootBag
	@param player Player
]=]
function LootBag:ReplicateLootForPlayer(player: Player)
	local loot = LootServer.GetBagLoot(self.Instance)
	local entry = if loot ~= nil then loot[player] else nil
	self.LootProperty:SetFor(player, entry)
end

--[=[
	Distance check between `player`'s character and the bag.
	@within LootBag
	@param player Player
	@return boolean
]=]
function LootBag:IsPlayerInRange(player: Player): boolean
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root == nil then
		return false
	end
	local bag = self.Instance :: BasePart
	return (root.Position - bag.Position).Magnitude <= MAX_LOOT_DISTANCE
end

return LootBag
