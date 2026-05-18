--!strict

--[=[
	@class FishingSpotClient
	Client-side companion to the server `FishingSpot` component. Subscribes to
	its owner-filtered `Active` pulse signal and to the `State`, `Frenzy`, and
	`FrenzyExpiresAt` properties. The billboard is only registered for the
	local player and only while they are (or recently were) actively fishing
	this spot — same per-player visibility model as `OreNodeClient` /
	`TreeNodeClient`. The pulse cadence on the server is independent of the
	catch tick cadence, so the billboard stays alive even when ticks are
	infrequent.

	After `BAR_VISIBILITY_SECONDS` without an `Active` pulse, the billboard
	auto-prunes. State and frenzy values flow through the re-exposed Comm
	properties so renderers can subscribe directly.
]=]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Billboards = require(ReplicatedStorage.Shared.React.Billboards.Billboards)
local FishingSpotBillboard = require(ReplicatedStorage.Shared.React.Billboards.FishingSpotBillboard)

local e = React.createElement

local BAR_VISIBILITY_SECONDS = 5

--[=[
	@type State "Normal" | "Frenzy"
	@within FishingSpotClient
]=]
export type State = "Normal" | "Frenzy"

local FishingSpotClient = Component.new({
	Tag = "FishingSpot",
	Ancestors = { Workspace },
})

function FishingSpotClient:Construct()
	self.Trove = Trove.new()
	self.BillboardKey = nil :: string?
	self.ExpireThread = nil :: thread?

	self.Comm = Comm.ClientComm.new(self.Instance, false, "FishingSpot")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:GetProperty("State")
	self.FrenzyProperty = self.Comm:GetProperty("Frenzy")
	self.FrenzyExpiresAtProperty = self.Comm:GetProperty("FrenzyExpiresAt")
	self.ActiveSignal = self.Comm:GetSignal("Active")

	self.ActiveSignal:Connect(function()
		self:HandleActivePulse()
	end)
end

function FishingSpotClient:Stop()
	if self.ExpireThread ~= nil then
		task.cancel(self.ExpireThread)
		self.ExpireThread = nil
	end
	if self.BillboardKey ~= nil then
		Billboards.Remove(self.BillboardKey)
		self.BillboardKey = nil
	end
	self.Trove:Destroy()
end

--[=[
	Records / refreshes the local-player billboard registration in response to
	a server `Active` pulse. Registers on first arrival, resets the expire
	timer on every subsequent arrival.
	@within FishingSpotClient
]=]
function FishingSpotClient:HandleActivePulse()
	if self.BillboardKey == nil then
		local root = self.Instance:WaitForChild("Root", 5)
		if root == nil or not root:IsA("BasePart") then
			return
		end
		self.BillboardKey = `FishingSpot:{HttpService:GenerateGUID(false)}`
		Billboards.Set(self.BillboardKey, {
			Adornee = root,
			Native = {},
			Render = function()
				return e(FishingSpotBillboard, {
					Node = self,
				})
			end,
		})
	end

	if self.ExpireThread ~= nil then
		task.cancel(self.ExpireThread)
	end
	self.ExpireThread = task.delay(BAR_VISIBILITY_SECONDS, function()
		self.ExpireThread = nil
		self:ExpireBillboard()
	end)
end

--[=[
	Removes the billboard registration after the local player has gone
	`BAR_VISIBILITY_SECONDS` without a pulse from this spot.
	@within FishingSpotClient
]=]
function FishingSpotClient:ExpireBillboard()
	if self.BillboardKey == nil then
		return
	end
	Billboards.Remove(self.BillboardKey)
	self.BillboardKey = nil
end

return FishingSpotClient
