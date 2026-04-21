local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local BLACK = Color3.new(0, 0, 0)
local PURPLE = Color3.fromRGB(128, 0, 128)

local IslandTeleporterClient = Component.new({
	Tag = "IslandTeleporter",
	Ancestors = { workspace },
})

function IslandTeleporterClient:Construct()
	self.Trove = Trove.new()
	self.ChargeStartTime = nil
	self.ChargeDuration = nil

	self.Parts = {}
	if self.Instance:IsA("BasePart") then
		table.insert(self.Parts, self.Instance)
	end
	for _, desc in self.Instance:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(self.Parts, desc)
		end
	end
end

function IslandTeleporterClient:Start()
	local comm = Comm.ClientComm.new(self.Instance, false, "IslandTeleporter")
	self.Trove:Add(comm)

	comm:GetSignal("ChargeStarted"):Connect(function(startTime: number, duration: number)
		self.ChargeStartTime = startTime
		self.ChargeDuration = duration
	end)

	comm:GetSignal("ChargeEnded"):Connect(function()
		self.ChargeStartTime = nil
		self.ChargeDuration = nil
		self:SetColor(BLACK)
	end)
end

function IslandTeleporterClient:Stop()
	self.Trove:Destroy()
end

function IslandTeleporterClient:SetColor(color: Color3)
	for _, part in self.Parts do
		part.Color = color
	end
end

function IslandTeleporterClient:RenderSteppedUpdate()
	if self.ChargeStartTime == nil then
		return
	end

	local elapsed = Workspace:GetServerTimeNow() - self.ChargeStartTime
	local alpha = math.clamp(elapsed / self.ChargeDuration, 0, 1)
	self:SetColor(BLACK:Lerp(PURPLE, alpha))
end

return IslandTeleporterClient
