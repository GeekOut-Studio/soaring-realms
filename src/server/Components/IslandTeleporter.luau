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

local checkRadius = t.numberPositive
local checkDestination = t.keyOf(IslandDefs)

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

function IslandTeleporter:Construct()
	self.State = State.Idle
	self.PlayersInZone = {}
	self.StateThread = nil
	self.Accumulator = 0

	local radius = self.Instance:GetAttribute("TeleporterRadius")
	local destination = self.Instance:GetAttribute("TeleporterDestination")
	local name = self.Instance:GetFullName()

	local radiusOk, radiusErr = checkRadius(radius)
	assert(radiusOk, `{name}: TeleporterRadius - {radiusErr}`)

	local destOk, destErr = checkDestination(destination)
	assert(destOk, `{name}: TeleporterDestination - {destErr}`)

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

function IslandTeleporter:CancelStateThread()
	if self.StateThread ~= nil then
		task.cancel(self.StateThread)
		self.StateThread = nil
	end
end

function IslandTeleporter:IsInZone(position: Vector3): boolean
	local dx = position.X - self.ZoneCenter.X
	local dz = position.Z - self.ZoneCenter.Z
	if math.abs(dx) + math.abs(dz) > self.Radius * 2 then
		return false
	end
	return dx * dx + dz * dz <= self.Radius * self.Radius
		and math.abs(position.Y - self.ZoneCenter.Y) <= self.Radius / 2
end

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
