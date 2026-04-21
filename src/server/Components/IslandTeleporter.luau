local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local IslandDefs = require(ReplicatedStorage.Shared.Defs.IslandDefs)
local TeleportServer = require(ServerScriptService.Server.Servers.TeleportServer)

type IslandKind = IslandDefs.IslandKind

local CHARGE_TIME = 5
local COOLDOWN_TIME = 3

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

	self.Radius = self.Instance:GetAttribute("TeleporterRadius") :: number
	self.Destination = self.Instance:GetAttribute("TeleporterDestination") :: IslandKind

	local pivotPos = self.Instance:GetPivot().Position
	self.ZoneCenter = pivotPos + Vector3.new(0, self.Radius / 2, 0)
end

function IslandTeleporter:Start() end

function IslandTeleporter:Stop()
	self:CancelStateThread()
end

function IslandTeleporter:CancelStateThread()
	if self.StateThread then
		task.cancel(self.StateThread)
		self.StateThread = nil
	end
end

function IslandTeleporter:IsInZone(position: Vector3): boolean
	local dx = position.X - self.ZoneCenter.X
	local dz = position.Z - self.ZoneCenter.Z
	return dx * dx + dz * dz <= self.Radius * self.Radius
		and math.abs(position.Y - self.ZoneCenter.Y) <= self.Radius / 2
end

function IslandTeleporter:GetPlayersInZone(): { Player }
	local players = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local position = character:GetPivot().Position
			if self:IsInZone(position) then
				table.insert(players, player)
			end
		end
	end
	return players
end

function IslandTeleporter:EnterChargingUp()
	self.State = State.ChargingUp
	self.StateThread = task.delay(CHARGE_TIME, function()
		self.StateThread = nil
		local players = {}
		for player in self.PlayersInZone do
			table.insert(players, player)
		end
		TeleportServer.TeleportToIslandAsync(players, self.Destination)
		self.PlayersInZone = {}
		self.State = State.CoolingDown
		self.StateThread = task.delay(COOLDOWN_TIME, function()
			self.StateThread = nil
			self.State = State.Idle
		end)
	end)
end

function IslandTeleporter:HeartbeatUpdate()
	if self.State == State.CoolingDown then
		return
	end

	local newZone = {}
	for _, player in self:GetPlayersInZone() do
		newZone[player] = true
	end
	self.PlayersInZone = newZone

	local isEmpty = next(self.PlayersInZone) == nil

	if self.State == State.Idle then
		if not isEmpty then
			self:EnterChargingUp()
		end
	elseif self.State == State.ChargingUp then
		if isEmpty then
			self:CancelStateThread()
			self.State = State.Idle
		end
	end
end

return IslandTeleporter
