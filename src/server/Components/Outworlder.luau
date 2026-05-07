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

local CombatServer = require(ServerScriptService.Server.Servers.CombatServer)
local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local HealthTypes = require(ReplicatedStorage.Shared.Types.HealthTypes)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)
local OutworlderShared = require(ReplicatedStorage.Shared.Components.OutworlderShared)

type CombatSession = CombatTypes.CombatSession

type Action = ActionTypes.Action
type StopReason = ActionTypes.StopReason
type MovementMode = MovementTypes.MovementMode
type Equipment = EquipmentTypes.Equipment

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
	@prop MaxStamina number
	@within Outworlder
	Authoritative max stamina. Mirrored to the owning player only via the `MaxStamina` Comm
	property. Currently seeded from `MovementTypes.MaxStamina`, but will be computed from
	Skills and other factors in the future.
]=]

--[=[
	@prop Stamina number
	@within Outworlder
	Authoritative stamina value (0..MaxStamina). Mirrored to the owning player only via
	the `Stamina` Comm property.
]=]

--[=[
	@prop MaxHealth number
	@within Outworlder
	Authoritative max health. Mirrored to the owning player only via the `MaxHealth` Comm
	property. Currently seeded from `HealthTypes.DefaultMaxHealth`, but will be computed
	from Skills and other factors in the future.
]=]

--[=[
	@prop Health number
	@within Outworlder
	Authoritative current health (0..MaxHealth). Mirrored to the owning player only via
	the `Health` Comm property.
]=]

--[=[
	@prop AnimationTracks {[string]: AnimationTrack}
	@within Outworlder
	Cache of `AnimationTrack`s lazily loaded by `AnimationPlay`. Keyed by
	the animation name from `AnimationDefs`.
]=]

--[=[
	@prop EquipmentIdleAnimations {[string]: true}
	@within Outworlder
	Set of idle-animation names currently driven by equipped items. Diffed on
	every equipment change to start newly added idles and stop removed ones.
]=]

--[=[
	@prop CombatSession CombatSession?
	@within Outworlder
	Back-reference written by `CombatServer`. Non-nil exactly when the character is in
	combat. Polled each heartbeat to drive the replicated `InCombat` flag.
]=]

function Outworlder:Construct()
	self.CurrentAction = nil :: Action?
	self.Trove = Trove.new()
	self.AnimationTracks = {} :: { [string]: AnimationTrack }
	self.EquipmentIdleAnimations = {} :: { [string]: true }
	self.Animator = nil :: Animator?

	local player = Players:GetPlayerFromCharacter(self.Instance)
	assert(player ~= nil, `Outworlder character has no associated player: {self.Instance:GetFullName()}`)
	self.Player = player

	self.Comm = Comm.ServerComm.new(self.Instance, "Outworlder")
	self.Trove:Add(self.Comm)
	self.EquipmentProperty = self.Comm:CreateProperty("Equipment", EquipmentTypes.DefaultEquipment)
	self.MovementModeProperty = self.Comm:CreateProperty("MovementMode", MovementTypes.DefaultMode)
	self.MaxStamina = MovementTypes.MaxStamina
	self.MaxStaminaProperty = self.Comm:CreateProperty("MaxStamina", self.MaxStamina)
	self.StaminaProperty = self.Comm:CreateProperty("Stamina", self.MaxStamina)
	self.MaxHealth = HealthTypes.DefaultMaxHealth
	self.MaxHealthProperty = self.Comm:CreateProperty("MaxHealth", self.MaxHealth)
	self.HealthProperty = self.Comm:CreateProperty("Health", self.MaxHealth)
	self.InCombatProperty = self.Comm:CreateProperty("InCombat", false)
	self.ActionProgressProperty = self.Comm:CreateProperty("ActionProgress", nil)
	self.ActionFailedSignal = self.Comm:CreateSignal("ActionFailed")

	self.CombatSession = nil :: CombatSession?

	self.MovementMode = MovementTypes.DefaultMode :: MovementMode
	self.Stamina = self.MaxStamina
	self.StaminaRegenTimer = 0
	self.StaminaSendAccumulator = 0
	self.Health = self.MaxHealth
	self.HealthSendAccumulator = 0
	self.AirborneAccumulator = 0
	self.LastActionProgress = nil :: ActionTypes.ActionProgress?

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
		self:UpdateEquipmentIdleAnimations(equipment)
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
	self.MaxStaminaProperty:SetFor(self.Player, self.MaxStamina)
	self.StaminaProperty:SetFor(self.Player, self.Stamina)
	self.MaxHealthProperty:SetFor(self.Player, self.MaxHealth)
	self.HealthProperty:SetFor(self.Player, self.Health)
end

function Outworlder:Stop()
	if self.CurrentAction ~= nil then
		self.CurrentAction:Stop("Interrupted")
		self.CurrentAction = nil
	end
	CombatServer.Disengage(self)
	self:AnimationStopHardAll()
	self.Trove:Destroy()
end

--[=[
	Returns the team identifier for this combatant. Implements the `Combatant` interface.
	@within Outworlder
	@return string?
]=]
function Outworlder:GetTeam(): string?
	return "Players"
end

--[=[
	Returns the character's pivot CFrame (position + facing). Implements the `Combatant`
	interface for combat-system range and direction checks.
	@within Outworlder
	@return CFrame
]=]
function Outworlder:GetCFrame(): CFrame
	return self.Instance:GetPivot()
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
	Computes the current action's `ActionProgress` payload and replicates it to the
	owning player only when it differs from the last value sent. Pushes `nil` when
	there is no action, or the action exposes neither `CompletionTimestamp` nor
	`Alpha`. Called every Heartbeat after the action's `Update` runs.
	@within Outworlder
]=]
function Outworlder:ReplicateActionProgress()
	local action = self.CurrentAction
	local progress: ActionTypes.ActionProgress? = nil
	if action ~= nil and (action.CompletionTimestamp ~= nil or action.Alpha ~= nil) then
		progress = {
			Name = action.Name,
			CompletionTimestamp = action.CompletionTimestamp,
			Alpha = action.Alpha,
		}
	end

	local last = self.LastActionProgress
	if progress == nil and last == nil then
		return
	end
	if
		progress ~= nil
		and last ~= nil
		and progress.Name == last.Name
		and progress.CompletionTimestamp == last.CompletionTimestamp
		and progress.Alpha == last.Alpha
	then
		return
	end

	self.LastActionProgress = progress
	self.ActionProgressProperty:SetFor(self.Player, progress)
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
	Sends an "action failed" notification to the owning player. The message
	describes why an attempted action couldn't proceed (e.g. failed requirements
	check). Future client UI subscribes to the `ActionFailed` Comm signal to
	render a transient toast.
	@within Outworlder
	@param message string
]=]
function Outworlder:NotifyActionFailed(message: string)
	self.ActionFailedSignal:Fire(self.Player, message)
end

--[=[
	Pivots the character to face `targetPoint` on the horizontal plane. Vertical
	component of the delta is discarded so the character stays upright. No-ops when
	the flat delta is approximately zero (avoids producing a `NaN` look-direction
	when the target is directly above/below or coincident with the character).
	@within Outworlder
	@param targetPoint Vector3
]=]
function Outworlder:FaceTowards(targetPoint: Vector3)
	local currentPosition = self.Instance:GetPivot().Position
	local delta = (targetPoint - currentPosition) * Vector3.new(1, 0, 1)
	if delta:FuzzyEq(Vector3.zero) then
		return
	end
	self.Instance:PivotTo(CFrame.lookAlong(currentPosition, delta))
end

--[=[
	Validates a client request to change movement mode.
	Sprint requests are rejected when stamina is exhausted. Crouch requests are rejected
	when the character is airborne so we never enter a crouch in mid-air. All other
	transitions accept.
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
	if mode == "Crouch" and not OutworlderShared.IsGrounded(self.ControllerManager) then
		return false
	end
	self:SetMovementMode(mode)
	return true
end

--[=[
	Returns the character's `Animator`, lazily resolving it from the Humanoid on
	first access and caching the result.
	@within Outworlder
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

local function getOrLoadTrack(self, kind: string): AnimationTrack
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
	@param kind string
]=]
function Outworlder:AnimationPlay(kind: string, ...: any)
	getOrLoadTrack(self, kind):Play(...)
end

--[=[
	Plays the animation identified by `kind` scaled so that one full play takes
	approximately `duration` seconds. Speed is computed as `track.Length /
	duration`; if the track's `Length` is not yet populated (animation data still
	loading on first use) or `duration` is non-positive, falls back to native
	speed. Subsequent calls after the first will use the correct speed.
	@within Outworlder
	@param kind string
	@param duration number
]=]
function Outworlder:AnimationPlayWithDuration(kind: string, duration: number)
	local track = getOrLoadTrack(self, kind)
	local speed = if track.Length > 0 and duration > 0 then track.Length / duration else 1
	track:Play(nil, nil, speed)
end

--[=[
	Stops the animation identified by `kind`. Returns silently if the track was
	never loaded — stopping an animation we are definitely not playing is a
	no-op. Extra arguments are forwarded to `AnimationTrack:Stop` (`fadeTime`).
	@within Outworlder
	@param kind string
]=]
function Outworlder:AnimationStop(kind: string, ...: any)
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
	@param kind string
]=]
function Outworlder:AnimationStopHard(kind: string)
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
]=]
function Outworlder:AnimationStopHardAll()
	for _, track in self.AnimationTracks do
		track:AdjustWeight(0, 0)
		track:Stop(0)
	end
end

--[=[
	Returns whether the track for `kind` is currently loaded and playing. Returns
	`false` if the track was never loaded — consistent with the cache-or-nothing
	semantics of the rest of the animation API.
	@within Outworlder
	@param kind string
	@return boolean
]=]
function Outworlder:AnimationIsPlaying(kind: string): boolean
	local track = self.AnimationTracks[kind]
	return track ~= nil and track.IsPlaying
end

--[=[
	Reconciles the set of equipment-driven idle animations with `equipment`.
	Each item's `ItemDef.IdleAnimation` (when present) contributes one looping
	idle track; multiple equipped items layer naturally via `AnimationPriority`.
	Newly added kinds are played, removed kinds are stopped.
	@within Outworlder
	@param equipment Equipment
]=]
function Outworlder:UpdateEquipmentIdleAnimations(equipment: Equipment)
	local desired: { [string]: true } = {}
	for _, item in equipment do
		local def = ItemDefs[item.Kind]
		if def ~= nil and def.IdleAnimation ~= nil then
			desired[def.IdleAnimation] = true
		end
	end

	for kind in self.EquipmentIdleAnimations do
		if not desired[kind] then
			self:AnimationStop(kind)
		end
	end
	for kind in desired do
		if not self.EquipmentIdleAnimations[kind] then
			self:AnimationPlay(kind)
		end
	end
	self.EquipmentIdleAnimations = desired
end

local function updateCrouchAnimations(self, isGrounded: boolean, isMoving: boolean)
	local inCrouch = self.MovementMode == "Crouch"
	local wantIdle = inCrouch
	local wantWalk = inCrouch and isMoving and isGrounded

	if not wantWalk and self:AnimationIsPlaying("CrouchWalk") then
		self:AnimationStop("CrouchWalk")
	end
	if not wantIdle and self:AnimationIsPlaying("CrouchIdle") then
		self:AnimationStop("CrouchIdle")
	end
	if wantIdle and not self:AnimationIsPlaying("CrouchIdle") then
		self:AnimationPlay("CrouchIdle")
	end
	if wantWalk and not self:AnimationIsPlaying("CrouchWalk") then
		self:AnimationPlay("CrouchWalk")
	end
end

function Outworlder:HeartbeatUpdate(dt: number)
	local isMoving = OutworlderShared.IsMoving(self.ControllerManager)
	local isGrounded = OutworlderShared.IsGrounded(self.ControllerManager)

	if self.CurrentAction ~= nil and not self.CurrentAction.AllowsMovement and (isMoving or not isGrounded) then
		self.CurrentAction:Stop("Interrupted")
		self.CurrentAction = nil
	end

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

	self:ReplicateActionProgress()
	local drained = OutworlderShared.StepStaminaDrain(self.Stamina, self.MovementMode, isMoving, dt)
	if drained < self.Stamina then
		self.Stamina = drained
		self.StaminaRegenTimer = MovementTypes.StaminaRegenDelaySeconds
	else
		self.StaminaRegenTimer = math.max(0, self.StaminaRegenTimer - dt)
		if self.StaminaRegenTimer <= 0 then
			self.Stamina = math.min(self.MaxStamina, self.Stamina + MovementTypes.StaminaRegenPerSecond * dt)
		end
	end
	if self.MovementMode == "Sprint" and self.Stamina <= 0 then
		self:SetMovementMode("Walk")
	end

	if self.MovementMode == "Crouch" then
		if isGrounded then
			self.AirborneAccumulator = 0
		else
			self.AirborneAccumulator += dt
			if self.AirborneAccumulator >= MovementTypes.CrouchAirborneGraceSeconds then
				self.AirborneAccumulator = 0
				self:SetMovementMode("Walk")
			end
		end
	else
		self.AirborneAccumulator = 0
	end

	updateCrouchAnimations(self, isGrounded, isMoving)

	self.StaminaSendAccumulator += dt
	if self.StaminaSendAccumulator >= MovementTypes.StaminaReplicationInterval then
		self.StaminaSendAccumulator = 0
		self.StaminaProperty:SetFor(self.Player, self.Stamina)
	end

	if self.Health < self.MaxHealth then
		self.Health = math.min(self.MaxHealth, self.Health + HealthTypes.HealthRegenPerSecond * dt)
	end
	self.HealthSendAccumulator += dt
	if self.HealthSendAccumulator >= HealthTypes.HealthReplicationInterval then
		self.HealthSendAccumulator = 0
		self.HealthProperty:SetFor(self.Player, self.Health)
	end

	local inCombat = self.CombatSession ~= nil
	if inCombat ~= self.InCombatProperty:Get() then
		self.InCombatProperty:Set(inCombat)
	end
end

--[=[
	Returns the character's authoritative current health. Implements `DamageTarget`.
	@within Outworlder
	@return number
]=]
function Outworlder:GetHealth(): number
	return self.Health
end

--[=[
	Sets the character's authoritative health, clamped to `[0, MaxHealth]`, and pushes the
	new value to the owning client immediately (bypassing the replication throttle so a
	damage hit feels instant on the HUD). On reaching zero, kills the character via the
	Humanoid so the default respawn pipeline takes over. Implements `DamageTarget`.
	@within Outworlder
	@param value number
]=]
function Outworlder:SetHealth(value: number)
	self.Health = math.clamp(value, 0, self.MaxHealth)
	self.HealthSendAccumulator = 0
	self.HealthProperty:SetFor(self.Player, self.Health)
	if self.Health <= 0 then
		local humanoid = self.Instance:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			humanoid.Health = -100
		end
	end
end

return Outworlder
