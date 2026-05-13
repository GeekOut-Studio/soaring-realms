--!strict

--[=[
	@class DenizenClient
	Client-side companion to the server `Denizen` component. Subscribes to the
	denizen's Comm (`Health`, `MaxHealth`, `InCombat`) and registers a
	`Billboards` entry rendering an overhead `CombatantBillboard` whenever the
	denizen is in combat or has taken damage within the last
	`BAR_VISIBILITY_SECONDS`. When neither condition holds, the entry is
	unregistered so the bar fully disappears.

	Damage detection is derived client-side from `HealthProperty` drops (any
	transition to a lower value stamps `LastDamagedAt`) — the server does not
	need a separate `LastDamagedTime` Comm property.

	The Comm property handles (`HealthProperty`, `MaxHealthProperty`,
	`InCombatProperty`) are part of the public surface: external consumers
	(React components, other client systems) may read them via `:Get()` or
	subscribe with `Observing.observeCommProperty`. Treat renames or removals
	as breaking changes.
]=]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Billboards = require(ReplicatedStorage.Shared.React.Billboards.Billboards)
local CombatantBillboard = require(ReplicatedStorage.Shared.React.Billboards.CombatantBillboard)
local Observing = require(ReplicatedStorage.Shared.Observing)

local e = React.createElement

local BAR_VISIBILITY_SECONDS = 5

local DenizenClient = Component.new({
	Tag = "Denizen",
	Ancestors = { Workspace },
})

--[=[
	@prop HealthProperty any
	@within DenizenClient
	Comm property mirroring the server's authoritative `Denizen.Health`.
	Public: external consumers may read via `:Get()` or subscribe with
	`Observing.observeCommProperty`.
]=]

--[=[
	@prop MaxHealthProperty any
	@within DenizenClient
	Comm property mirroring `Denizen.MaxHealth`. Public — see `HealthProperty`.
]=]

--[=[
	@prop InCombatProperty any
	@within DenizenClient
	Comm property mirroring whether the denizen currently has a `CombatSession`
	on the server. Public — see `HealthProperty`.
]=]

function DenizenClient:Construct()
	self.Trove = Trove.new()

	self.LastReplicatedHealth = nil :: number?
	self.LastDamagedAt = nil :: number?

	self.BillboardKey = `Denizen:{HttpService:GenerateGUID(false)}`
	self.BillboardActive = false
	self.ExpireThread = nil :: thread?

	self.Comm = Comm.ClientComm.new(self.Instance, false, "Denizen")
	self.Trove:Add(self.Comm)
	self.MaxHealthProperty = self.Comm:GetProperty("MaxHealth")
	self.HealthProperty = self.Comm:GetProperty("Health")
	self.InCombatProperty = self.Comm:GetProperty("InCombat")
end

--[=[
	`HealthProperty` observer. The first replication just seeds
	`LastReplicatedHealth`; subsequent decreases stamp `LastDamagedAt` and
	refresh billboard visibility. The component does not cache `Health` —
	consumers should read `HealthProperty:Get()` directly.
	@within DenizenClient
	@param value number
]=]
function DenizenClient:HandleHealth(value: number)
	local previous = self.LastReplicatedHealth
	self.LastReplicatedHealth = value
	if previous ~= nil and value < previous then
		self.LastDamagedAt = os.clock()
		self:RefreshBillboardVisibility()
	end
end

function DenizenClient:Start()
	self.Trove:Add(Observing.observeCommProperty(self.HealthProperty, function(value: number)
		self:HandleHealth(value)
		return nil
	end))
	self.Trove:Add(Observing.observeCommProperty(self.InCombatProperty, function(_value: boolean)
		self:RefreshBillboardVisibility()
		return nil
	end))
end

function DenizenClient:Stop()
	if self.ExpireThread ~= nil then
		task.cancel(self.ExpireThread)
		self.ExpireThread = nil
	end
	if self.BillboardActive then
		Billboards.Remove(self.BillboardKey)
		self.BillboardActive = false
	end
	self.Trove:Destroy()
end

--[=[
	Recomputes whether the overhead billboard should be visible and
	(un)registers a `Billboards` entry accordingly. Visible whenever the
	denizen is in combat or has taken damage within
	`BAR_VISIBILITY_SECONDS`. Schedules a delayed re-check when visibility
	hangs on a damage-tail timeout.
	@within DenizenClient
]=]
function DenizenClient:RefreshBillboardVisibility()
	local now = os.clock()
	local inCombat = self.InCombatProperty:Get() :: boolean
	local damagedRecently = self.LastDamagedAt ~= nil and (now - self.LastDamagedAt) < BAR_VISIBILITY_SECONDS
	local shouldShow = inCombat or damagedRecently

	if shouldShow then
		if not self.BillboardActive then
			self:RegisterBillboard()
		end
		if self.ExpireThread ~= nil then
			task.cancel(self.ExpireThread)
			self.ExpireThread = nil
		end
		if not inCombat and self.LastDamagedAt ~= nil then
			local remaining = BAR_VISIBILITY_SECONDS - (now - self.LastDamagedAt)
			self.ExpireThread = task.delay(remaining, function()
				self.ExpireThread = nil
				self:RefreshBillboardVisibility()
			end)
		end
	else
		if self.BillboardActive then
			Billboards.Remove(self.BillboardKey)
			self.BillboardActive = false
		end
		if self.ExpireThread ~= nil then
			task.cancel(self.ExpireThread)
			self.ExpireThread = nil
		end
	end
end

--[=[
	Adds the overhead billboard entry. Anchors to the denizen's `PrimaryPart`
	— denizens use a custom rig with no `Head` part, so `PrimaryPart` is the
	canonical adornee for cross-rig overhead anchoring.
	@within DenizenClient
]=]
function DenizenClient:RegisterBillboard()
	local adornee = self.Instance.PrimaryPart
	if adornee == nil then
		return
	end
	Billboards.Set(self.BillboardKey, {
		Adornee = adornee,
		Native = {
			Size = UDim2.fromScale(4, 0.6),
			StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
		},
		Render = function()
			return e(CombatantBillboard, {
				HealthProperty = self.HealthProperty,
				MaxHealthProperty = self.MaxHealthProperty,
			})
		end,
	})
	self.BillboardActive = true
end

return DenizenClient
