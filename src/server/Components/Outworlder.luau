--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Action = require(ReplicatedStorage.Shared.Action)

type Action = Action.Action
type StopReason = Action.StopReason

local Outworlder = Component.new({
	Tag = "Outworlder",
	Ancestors = { Workspace },
})

function Outworlder:Construct()
	self.CurrentAction = nil :: Action?
end

function Outworlder:Stop()
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop("Interrupted")
		self.CurrentAction = nil
	end
end

function Outworlder:StartAction(action: Action)
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop("Interrupted")
	end
	self.CurrentAction = action
end

function Outworlder:StopCurrentAction(reason: StopReason?)
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop(if reason ~= nil then reason else "Interrupted")
		self.CurrentAction = nil
	end
end

function Outworlder:AllowsMovement(): boolean
	if self.CurrentAction == nil then
		return true
	end
	return self.CurrentAction.AllowsMovement
end

function Outworlder:HeartbeatUpdate(dt: number)
	if self.CurrentAction == nil then
		return
	end

	local result = self.CurrentAction:Update(dt)
	if result == "Complete" then
		self.CurrentAction:Stop("Completed")
		self.CurrentAction = nil
	elseif result == "Fail" then
		self.CurrentAction:Stop("Failed")
		self.CurrentAction = nil
	end
end

return Outworlder
