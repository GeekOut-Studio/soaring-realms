local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local RUNE_WAIT_TIMEOUT = 10

local IslandTeleporterClient = Component.new({
	Tag = "IslandTeleporter",
	Ancestors = { workspace },
})

function IslandTeleporterClient:Construct()
	self.Trove = Trove.new()
	self.ChargeStartTime = nil
	self.ChargeDuration = nil
end

function IslandTeleporterClient:Start()
	local name = self.Instance:GetFullName()
	local rune = self.Instance:WaitForChild("Rune", RUNE_WAIT_TIMEOUT)
	assert(rune ~= nil, `{name}: Rune did not replicate within {RUNE_WAIT_TIMEOUT}s`)
	assert(rune:IsA("BasePart"), `{name}: Rune must be a BasePart`)
	self.Rune = rune
	self.RuneOriginOffset = self.Instance:GetPivot():ToObjectSpace(rune.CFrame)
	self.RuneHeight = rune.Size.Y

	local comm = Comm.ClientComm.new(self.Instance, false, "IslandTeleporter")
	self.Trove:Add(comm)

	comm:GetSignal("ChargeStarted"):Connect(function(startTime: number, duration: number)
		self.ChargeStartTime = startTime
		self.ChargeDuration = duration
	end)

	comm:GetSignal("ChargeEnded"):Connect(function()
		self.ChargeStartTime = nil
		self.ChargeDuration = nil
		self.Rune.CFrame = self.Instance:GetPivot():ToWorldSpace(self.RuneOriginOffset)
	end)
end

function IslandTeleporterClient:Stop()
	self.Trove:Destroy()
end

function IslandTeleporterClient:RenderSteppedUpdate()
	if self.ChargeStartTime == nil then
		return
	end

	local elapsed = Workspace:GetServerTimeNow() - self.ChargeStartTime
	local alpha = math.clamp(elapsed / self.ChargeDuration, 0, 1)
	local baseCFrame = self.Instance:GetPivot():ToWorldSpace(self.RuneOriginOffset)
	self.Rune.CFrame = baseCFrame * CFrame.new(0, alpha * self.RuneHeight, 0)
end

return IslandTeleporterClient
