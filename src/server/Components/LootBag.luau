--!strict

--[=[
	@class LootBag
	Server component for the `LootBag` tag. The spatial + Comm view of a
	loot pile; the loot data itself lives in `LootServer` for the bag's
	whole lifetime (see `LootServer.GetBagLoot` / `ClaimLoot` /
	`DiscardBag`). Spawned by `LootServer.SpawnBag`; never authored.

	On `Construct`, reads the bag's loot map from `LootServer` and seeds
	`LootProperty:SetFor(player, loot)` for each eligible player. Other
	players see the property's default value (`nil`) and
	`LootBagClient` renders nothing for them.

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
	self.Comm:BindFunction("Loot", function(player: Player)
		return self:HandleLoot(player)
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
	Server-bound `Loot` function. Validates proximity, delegates the
	authoritative claim to `LootServer.ClaimLoot`, clears the per-player
	property on success, and destroys the bag when no claims remain.
	@within LootBag
	@param player Player
	@return boolean -- `true` if the loot was claimed, `false` otherwise.
]=]
function LootBag:HandleLoot(player: Player): boolean
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root == nil then
		return false
	end
	local bag = self.Instance :: BasePart
	if (root.Position - bag.Position).Magnitude > MAX_LOOT_DISTANCE then
		return false
	end

	if not LootServer.ClaimLoot(self.Instance, player) then
		return false
	end

	self.LootProperty:SetFor(player, nil)

	if LootServer.IsBagEmpty(self.Instance) then
		self.Instance:Destroy()
	end
	return true
end

return LootBag
