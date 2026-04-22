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
	self.currentAction = nil :: Action?
end

function Outworlder:Stop()
	if self.currentAction ~= nil then
		self.currentAction:Stop("Interrupted")
		self.currentAction = nil
	end
end

function Outworlder:StartAction(action: Action)
	if self.currentAction ~= nil then
		self.currentAction:Stop("Interrupted")
	end
	self.currentAction = action
end

function Outworlder:StopCurrentAction(reason: StopReason?)
	if self.currentAction ~= nil then
		self.currentAction:Stop(if reason ~= nil then reason else "Interrupted")
		self.currentAction = nil
	end
end

function Outworlder:AllowsMovement(): boolean
	if self.currentAction == nil then
		return true
	end
	return self.currentAction.AllowsMovement
end

function Outworlder:HeartbeatUpdate(dt: number)
	if self.currentAction == nil then
		return
	end

	local result = self.currentAction:Update(dt)
	if result == "Complete" then
		self.currentAction:Stop("Completed")
		self.currentAction = nil
	elseif result == "Fail" then
		self.currentAction:Stop("Failed")
		self.currentAction = nil
	end
end

return Outworlder
