--!strict

--[=[
	@class Outworlder
	Component attached to player characters in the world. Owns the currently running
	Action, drives its update loop, and holds authoritative movement state (mode + stamina)
	replicated to clients via per-instance Comm properties.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)
local OutworlderShared = require(ReplicatedStorage.Shared.Components.OutworlderShared)

type Action = ActionTypes.Action
type StopReason = ActionTypes.StopReason
type MovementMode = MovementTypes.MovementMode
type AnimationKind = AnimationDefs.AnimationKind

local WAIT_FOR_CHILD_TIMEOUT = 10

local Outworlder = Component.new({
	Tag = "Outworlder",
	Ancestors = { Workspace },
})

--[=[
	@prop CurrentAction Action?
	@within Outworlder
	The action currently being executed, or `nil` if the character is idle.
]=]

--[=[
	@prop MovementMode MovementMode
	@within Outworlder
	Authoritative movement mode. Mirrored to the `MovementMode` Comm property.
]=]

--[=[
	@prop Stamina number
	@within Outworlder
	Authoritative stamina value (0..MaxStamina). Mirrored to the owning player only via
	the `Stamina` Comm property.
]=]

--[=[
	@prop AnimationTracks {[AnimationKind]: AnimationTrack}
	@within Outworlder
	Cache of `AnimationTrack`s lazily loaded by `AnimationPlay`. Keyed by
	`AnimationKind` from `AnimationDefs`.
]=]

function Outworlder:Construct()
	self.CurrentAction = nil :: Action?
	self.Trove = Trove.new()
	self.AnimationTracks = {} :: { [AnimationKind]: AnimationTrack }
	self.Animator = nil :: Animator?

	local player = Players:GetPlayerFromCharacter(self.Instance)
	assert(player ~= nil, `Outworlder character has no associated player: {self.Instance:GetFullName()}`)
	self.Player = player

	self.Comm = Comm.ServerComm.new(self.Instance, "Outworlder")
	self.Trove:Add(self.Comm)
	self.EquipmentProperty = self.Comm:CreateProperty("Equipment", EquipmentTypes.DefaultEquipment)
	self.MovementModeProperty = self.Comm:CreateProperty("MovementMode", MovementTypes.DefaultMode)
	self.StaminaProperty = self.Comm:CreateProperty("Stamina", MovementTypes.MaxStamina)

	self.MovementMode = MovementTypes.DefaultMode :: MovementMode
	self.Stamina = MovementTypes.MaxStamina
	self.StaminaSendAccumulator = 0

	self.Comm:BindFunction("RequestSetMovementMode", function(callingPlayer, mode)
		if callingPlayer ~= self.Player then
			return false
		end
		if not t.string(mode) then
			return false
		end
		return self:HandleRequestSetMovementMode(mode)
	end)

	self.Trove:Add(EquipmentServer.ObserveEquipment(player, function(equipment)
		self.EquipmentProperty:Set(equipment)
	end))
end

function Outworlder:Start()
	self.ControllerManager =
		self.Instance:WaitForChild("ControllerManager", WAIT_FOR_CHILD_TIMEOUT) :: ControllerManager
	assert(
		self.ControllerManager ~= nil,
		`Outworlder character has no ControllerManager (is the Character Controller Library enabled?): {self.Instance:GetFullName()}`
	)

	OutworlderShared.ApplyMode(self.ControllerManager, self.MovementMode)
	self.StaminaProperty:SetFor(self.Player, self.Stamina)
end

function Outworlder:Stop()
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop("Interrupted")
		self.CurrentAction = nil
	end
	self:AnimationStopHardAll()
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

--[=[
	Sets the authoritative movement mode, applies the corresponding speed via
	`OutworlderShared`, and replicates via the `MovementMode` property.
	@within Outworlder
	@param mode MovementMode
]=]
function Outworlder:SetMovementMode(mode: MovementMode)
	if self.MovementMode == mode then
		return
	end
	self.MovementMode = mode
	OutworlderShared.ApplyMode(self.ControllerManager, mode)
	self.MovementModeProperty:Set(mode)
end

--[=[
	Validates a client request to change movement mode.
	Sprint requests are rejected when stamina is exhausted; all other transitions accept.
	@within Outworlder
	@param mode MovementMode
	@return boolean -- `true` if the request was accepted.
]=]
function Outworlder:HandleRequestSetMovementMode(mode: MovementMode): boolean
	if not MovementTypes.ModeSet[mode] then
		return false
	end
	if mode == "Sprint" and self.Stamina <= 0 then
		return false
	end
	self:SetMovementMode(mode)
	return true
end

--[=[
	Returns the character's `Animator`, lazily resolving it from the Humanoid on
	first access and caching the result.
	@within Outworlder
	@server
	@return Animator
]=]
function Outworlder:GetAnimator(): Animator
	if self.Animator ~= nil then
		return self.Animator
	end
	local humanoid = self.Instance:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator
	self.Animator = animator
	return animator
end

local function getOrLoadTrack(self, kind: AnimationKind): AnimationTrack
	local track = self.AnimationTracks[kind]
	if track ~= nil then
		return track
	end
	local animation = AnimationDefs[kind]
	track = self:GetAnimator():LoadAnimation(animation)
	self.AnimationTracks[kind] = track
	return track
end

--[=[
	Plays the animation identified by `kind`, loading it on first use. Any extra
	arguments are forwarded to `AnimationTrack:Play` (e.g. `fadeTime`, `weight`,
	`speed`).
	@within Outworlder
	@server
	@param kind AnimationKind
]=]
function Outworlder:AnimationPlay(kind: AnimationKind, ...: any)
	getOrLoadTrack(self, kind):Play(...)
end

--[=[
	Stops the animation identified by `kind`. Returns silently if the track was
	never loaded — stopping an animation we are definitely not playing is a
	no-op. Extra arguments are forwarded to `AnimationTrack:Stop` (`fadeTime`).
	@within Outworlder
	@server
	@param kind AnimationKind
]=]
function Outworlder:AnimationStop(kind: AnimationKind, ...: any)
	local track = self.AnimationTracks[kind]
	if track == nil then
		return
	end
	track:Stop(...)
end

--[=[
	Stops the animation identified by `kind` immediately by zeroing its weight
	before stopping with no fade. Returns silently if the track was never loaded.
	@within Outworlder
	@server
	@param kind AnimationKind
]=]
function Outworlder:AnimationStopHard(kind: AnimationKind)
	local track = self.AnimationTracks[kind]
	if track == nil then
		return
	end
	track:AdjustWeight(0, 0)
	track:Stop(0)
end

--[=[
	Hard-stops every cached animation track. Used to forcibly clear all
	animation state (e.g. on action interrupt).
	@within Outworlder
	@server
]=]
function Outworlder:AnimationStopHardAll()
	for _, track in self.AnimationTracks do
		track:AdjustWeight(0, 0)
		track:Stop(0)
	end
end

function Outworlder:HeartbeatUpdate(dt: number)
	if self.CurrentAction ~= nil then
		local result = self.CurrentAction:Update(dt)
		if result == "Complete" then
			self.CurrentAction:Stop("Completed")
			self.CurrentAction = nil
		elseif result == "Fail" then
			self.CurrentAction:Stop("Failed")
			self.CurrentAction = nil
		end
	end

	local isMoving = OutworlderShared.IsMoving(self.ControllerManager)
	self.Stamina = OutworlderShared.StepStamina(self.Stamina, self.MovementMode, isMoving, dt, true)
	if self.MovementMode == "Sprint" and self.Stamina <= 0 then
		self:SetMovementMode("Walk")
	end

	self.StaminaSendAccumulator += dt
	if self.StaminaSendAccumulator >= MovementTypes.StaminaReplicationInterval then
		self.StaminaSendAccumulator = 0
		self.StaminaProperty:SetFor(self.Player, self.Stamina)
	end
end

return Outworlder
