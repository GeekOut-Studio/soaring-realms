--!strict

--[=[
	@class LootBagClient
	Client-side companion to the server `LootBag` component. Subscribes
	to `LootProperty` (per-player via `RemoteProperty:SetFor`); when the
	local player has a non-empty loot pile, downloads the bag visual
	asset and parents it under the tagged part, plus a `ProximityPrompt`
	whose `Triggered` event opens the loot UI via `LootClient.OpenBag`.

	The component exposes the Comm handles (`LootProperty`,
	`LootOneFunction`, `LootAllFunction`) that `LootMenu` and
	`LootClient` reach into directly — no method wrappers.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local LootClient = require(ReplicatedStorage.Shared.Clients.LootClient)
local LootTypes = require(ReplicatedStorage.Shared.Types.LootTypes)
local Observing = require(ReplicatedStorage.Shared.Observing)

type PlayerLoot = LootTypes.PlayerLoot

local LOOT_BAG_ASSET_PATH = "Base/Misc/LootBag"
local PROMPT_ACTIVATION_DISTANCE = 6

local LootBagClient = Component.new({
	Tag = "LootBag",
	Ancestors = { Workspace },
})

--[=[
	@prop LootProperty any
	@within LootBagClient
	Per-player `RemoteProperty` mirroring the server's view of this
	player's loot pile. `LootMenu` observes it to render contents and to
	auto-close when it goes empty/nil.
]=]

function LootBagClient:Construct()
	self.Trove = Trove.new()
	self.VisualTrove = nil :: any

	self.Comm = Comm.ClientComm.new(self.Instance, false, "LootBag")
	self.Trove:Add(self.Comm)
	self.LootProperty = self.Comm:GetProperty("Loot")
	self.LootOneFunction = self.Comm:GetFunction("LootOne")
	self.LootAllFunction = self.Comm:GetFunction("LootAll")
end

function LootBagClient:Start()
	self.Trove:Add(Observing.observeCommProperty(self.LootProperty, function(loot: PlayerLoot?)
		if loot == nil or next(loot) == nil then
			self:HideVisual()
		else
			self:ShowVisual()
		end
		return nil
	end))
end

function LootBagClient:Stop()
	-- Filter on `self` so a stale-component teardown doesn't clobber a
	-- newer bag the player may have opened in the meantime.
	LootClient.CloseBag(self)
	self.Trove:Destroy()
end

--[=[
	Downloads the bag asset (if not already shown), parents it under the
	tagged part, and attaches a `ProximityPrompt` whose trigger opens
	the loot UI via `LootClient.OpenBag`. Idempotent — calling while
	already shown is a no-op.
	@within LootBagClient
]=]
function LootBagClient:ShowVisual()
	if self.VisualTrove ~= nil then
		return
	end
	local visualTrove = self.Trove:Extend()
	self.VisualTrove = visualTrove

	visualTrove:AddPromise(DownloadClient.Download(LOOT_BAG_ASSET_PATH):andThen(function(asset: Instance)
		if asset:IsA("BasePart") then
			asset.CFrame = (self.Instance :: BasePart).CFrame
		elseif asset:IsA("Model") then
			asset:PivotTo((self.Instance :: BasePart).CFrame)
		end
		asset.Parent = self.Instance
		visualTrove:Add(asset)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Loot"
		prompt.MaxActivationDistance = PROMPT_ACTIVATION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = self.Instance
		visualTrove:Add(prompt)
		visualTrove:Connect(prompt.Triggered, function()
			LootClient.OpenBag(self)
		end)
	end))
end

--[=[
	Tears down the rendered visual + prompt for this bag, if any. Also
	closes the loot UI if this bag was the active one, so a server-side
	"empty pile" update collapses the menu cleanly.
	@within LootBagClient
]=]
function LootBagClient:HideVisual()
	LootClient.CloseBag(self)
	if self.VisualTrove == nil then
		return
	end
	self.Trove:Remove(self.VisualTrove)
	self.VisualTrove = nil
end

return LootBagClient
