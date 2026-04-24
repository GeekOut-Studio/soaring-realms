--[=[
	@class IslandTeleporter
	Component placed on teleporter pads in the world. Tracks which players are inside
	the zone, charges up when occupied, and fires a server teleport when the charge
	completes. Broadcasts `ChargeStarted` and `ChargeEnded` signals to clients via Comm.

	Reads two instance attributes:
	- `TeleporterRadius` (number) — radius of the cylindrical trigger zone.
	- `TeleporterDestination` (IslandKind) — target island.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local IslandDefs = require(ReplicatedStorage.Shared.Defs.IslandDefs)
local t = require(ReplicatedStorage.Packages.t)
local TeleportServer = require(ServerScriptService.Server.Servers.TeleportServer)

type IslandKind = IslandDefs.IslandKind

local CHARGE_TIME = 5
local COOLDOWN_TIME = 3
local POLL_INTERVAL = 0.1

local State = {
	Idle = "Idle",
	ChargingUp = "ChargingUp",
	CoolingDown = "CoolingDown",
}

local IslandTeleporter = Component.new({
	Tag = "IslandTeleporter",
	Ancestors = { Workspace },
})

--[=[
	@prop Radius number
	@within IslandTeleporter
	Radius of the cylindrical trigger zone, read from the `TeleporterRadius` attribute.
]=]

--[=[
	@prop Destination IslandKind
	@within IslandTeleporter
	Target island, read from the `TeleporterDestination` attribute.
]=]

--[=[
	@prop State string
	@within IslandTeleporter
	Current state of the teleporter: `"Idle"`, `"ChargingUp"`, or `"CoolingDown"`.
]=]

function IslandTeleporter:Construct()
	self.State = State.Idle
	self.PlayersInZone = {}
	self.StateThread = nil
	self.Accumulator = 0

	local radius = self.Instance:GetAttribute("TeleporterRadius")
	local destination = self.Instance:GetAttribute("TeleporterDestination")
	local name = self.Instance:GetFullName()

	assert(t.numberPositive(radius), `{name}: bad TeleporterRadius`)
	assert(t.keyOf(IslandDefs)(destination), `{name}: bad TeleporterDestination`)

	self.Radius = radius :: number
	self.Destination = destination :: IslandKind

	local pivotPos = self.Instance:GetPivot().Position
	self.ZoneCenter = pivotPos + Vector3.new(0, self.Radius / 2, 0)

	self.Comm = Comm.ServerComm.new(self.Instance, "IslandTeleporter")
	self.ChargeStartedSignal = self.Comm:CreateSignal("ChargeStarted")
	self.ChargeEndedSignal = self.Comm:CreateSignal("ChargeEnded")
end

function IslandTeleporter:Stop()
	self:CancelStateThread()
	self.Comm:Destroy()
end

--[=[
	Cancels the active state thread (charge or cooldown timer) if one is running.
	@within IslandTeleporter
]=]
function IslandTeleporter:CancelStateThread()
	if self.StateThread ~= nil then
		task.cancel(self.StateThread)
		self.StateThread = nil
	end
end

--[=[
	Returns whether `position` is inside this teleporter's cylindrical zone.
	@within IslandTeleporter
	@param position Vector3
	@return boolean
]=]
function IslandTeleporter:IsInZone(position: Vector3): boolean
	local dx = position.X - self.ZoneCenter.X
	local dz = position.Z - self.ZoneCenter.Z
	if math.abs(dx) + math.abs(dz) > self.Radius * 2 then
		return false
	end
	return dx * dx + dz * dz <= self.Radius * self.Radius
		and math.abs(position.Y - self.ZoneCenter.Y) <= self.Radius / 2
end

--[=[
	Transitions to `ChargingUp`, fires `ChargeStarted` to all clients, and schedules
	the teleport. On completion, transitions to `CoolingDown` then back to `Idle`.
	@within IslandTeleporter
]=]
function IslandTeleporter:EnterChargingUp()
	self.State = State.ChargingUp
	self.ChargeStartedSignal:FireAll(Workspace:GetServerTimeNow(), CHARGE_TIME)
	self.StateThread = task.delay(CHARGE_TIME, function()
		self.StateThread = nil
		local players = {}
		for player in self.PlayersInZone do
			table.insert(players, player)
		end
		TeleportServer.TeleportToIslandAsync(players, self.Destination)
		self.ChargeEndedSignal:FireAll()
		self.PlayersInZone = {}
		self.State = State.CoolingDown
		self.StateThread = task.delay(COOLDOWN_TIME, function()
			self.StateThread = nil
			self.State = State.Idle
		end)
	end)
end

function IslandTeleporter:HeartbeatUpdate(dt: number)
	if self.State == State.CoolingDown then
		return
	end

	self.Accumulator += dt
	if self.Accumulator < POLL_INTERVAL then
		return
	end
	self.Accumulator = 0

	for player in self.PlayersInZone do
		local character = player.Character
		if character == nil or not self:IsInZone(character:GetPivot().Position) then
			self.PlayersInZone[player] = nil
		end
	end

	for _, player in Players:GetPlayers() do
		if self.PlayersInZone[player] == nil then
			local character = player.Character
			if character ~= nil and self:IsInZone(character:GetPivot().Position) then
				self.PlayersInZone[player] = true
			end
		end
	end

	local isEmpty = next(self.PlayersInZone) == nil

	if self.State == State.Idle then
		if not isEmpty then
			self:EnterChargingUp()
		end
	elseif self.State == State.ChargingUp then
		if isEmpty then
			self:CancelStateThread()
			self.ChargeEndedSignal:FireAll()
			self.State = State.Idle
		end
	end
end

return IslandTeleporter
