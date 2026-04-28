--!strict

--[=[
	@class Outworlder
	Component attached to player characters in the world. Owns the currently running
	Action and drives its update loop.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)

type Action = ActionTypes.Action
type StopReason = ActionTypes.StopReason

local Outworlder = Component.new({
	Tag = "Outworlder",
	Ancestors = { Workspace },
})

--[=[
	@prop CurrentAction Action?
	@within Outworlder
	The action currently being executed, or `nil` if the character is idle.
]=]

function Outworlder:Construct()
	self.CurrentAction = nil :: Action?
	self.Trove = Trove.new()

	self.Comm = Comm.ServerComm.new(self.Instance, "Outworlder")
	self.Trove:Add(self.Comm)
	self.EquipmentProperty = self.Comm:CreateProperty("Equipment", EquipmentTypes.DefaultEquipment)

	local player = Players:GetPlayerFromCharacter(self.Instance)
	assert(player ~= nil, `Outworlder character has no associated player: {self.Instance:GetFullName()}`)

	self.Trove:Add(EquipmentServer.ObserveEquipment(player, function(equipment)
		self.EquipmentProperty:Set(equipment)
	end))
end

function Outworlder:Stop()
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop("Interrupted")
		self.CurrentAction = nil
	end
	self.Trove:Destroy()
end

--[=[
	Begins executing `action`, interrupting any action already in progress.
	@within Outworlder
	@param action Action
]=]
function Outworlder:StartAction(action: Action)
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop("Interrupted")
	end
	self.CurrentAction = action
end

--[=[
	Stops the current action with `reason` (defaults to `"Interrupted"`).
	Does nothing if no action is running.
	@within Outworlder
	@param reason StopReason? -- Defaults to `"Interrupted"`.
]=]
function Outworlder:StopCurrentAction(reason: StopReason?)
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop(if reason ~= nil then reason else "Interrupted")
		self.CurrentAction = nil
	end
end

--[=[
	Returns whether the character is allowed to move given the current action.
	Always `true` when no action is running.
	@within Outworlder
	@return boolean
]=]
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
