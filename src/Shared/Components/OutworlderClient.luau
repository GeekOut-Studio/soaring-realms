--[=[
	@class OutworlderClient
	@client
	Runs on every client for every Outworlder. Handles two responsibilities:

	1. Renders each character's equipped gear by subscribing to the per-instance `Equipment`
	   Comm property and dispatching to per-slot renderers.
	2. For the local player only, wires keyboard input for sprint/crouch toggling and
	   reconciles optimistic mode predictions against the server-authoritative `MovementMode`
	   property. The actual physical effect of a mode (e.g. `BaseMoveSpeed`) is delegated to
	   `OutworlderShared.ApplyMode` so client-prediction and server-authoritative paths apply
	   the same logic.

	The Comm property handles (`HealthProperty`, `MaxHealthProperty`,
	`InCombatProperty`, etc.) are part of the public surface: external
	consumers (the HUD, billboard renderers, other client systems) may read
	them via `:Get()` or subscribe with `Observing.observeCommProperty`. Treat
	renames or removals as breaking changes.
]=]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local React = require(ReplicatedStorage.Packages.React)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)

local AbilityClient = require(ReplicatedStorage.Shared.Clients.AbilityClient)
local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)
local Billboards = require(ReplicatedStorage.Shared.React.Billboards.Billboards)
local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local CombatantBillboard = require(ReplicatedStorage.Shared.React.Billboards.CombatantBillboard)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)
local Observing = require(ReplicatedStorage.Shared.Observing)
local OutworlderShared = require(ReplicatedStorage.Shared.Components.OutworlderShared)

local e = React.createElement

local BAR_VISIBILITY_SECONDS = 5

type EquipmentSlot = EquipmentTypes.EquipmentSlot
type Equipment = EquipmentTypes.Equipment
type Item = InventoryTypes.Item
type MovementMode = MovementTypes.MovementMode
type ActionProgress = ActionTypes.ActionProgress

local WAIT_FOR_CHILD_TIMEOUT = 10

local SlotRenderers: { [string]: (asset: Instance, character: Model, trove: any) -> () } = {
	MainHandMelee = function(asset, character, trove)
		local rightHand = character:WaitForChild("RightHand", WAIT_FOR_CHILD_TIMEOUT) :: BasePart
		assert(rightHand ~= nil, `OutworlderClient: {character:GetFullName()} has no RightHand`)

		local charAttachment = rightHand:WaitForChild("RightGripAttachment", WAIT_FOR_CHILD_TIMEOUT) :: Attachment
		assert(
			charAttachment ~= nil,
			`OutworlderClient: {character:GetFullName()} has no RightGripAttachment on RightHand`
		)

		local assetAttachment = asset:FindFirstChild("RightGripAttachment", true) :: Attachment?
		assert(assetAttachment ~= nil, `OutworlderClient: asset {asset:GetFullName()} is missing RightGripAttachment`)

		local gripPart = assetAttachment.Parent :: BasePart

		local motor = Instance.new("Motor6D")
		motor.Part0 = rightHand
		motor.Part1 = gripPart
		motor.C0 = charAttachment.CFrame
		motor.C1 = assetAttachment.CFrame
		motor.Parent = gripPart
		trove:Add(motor)

		asset.Parent = character
	end,
}

local OutworlderClient = Component.new({
	Tag = "Outworlder",
	Ancestors = { Workspace },
})

--[=[
	@prop HealthProperty any
	@within OutworlderClient
	Comm property mirroring the server's authoritative `Outworlder.Health`.
	Public: external consumers may read via `:Get()` or subscribe with
	`Observing.observeCommProperty`.
]=]

--[=[
	@prop MaxHealthProperty any
	@within OutworlderClient
	Comm property mirroring `Outworlder.MaxHealth`. Public — see `HealthProperty`.
]=]

--[=[
	@prop InCombatProperty any
	@within OutworlderClient
	Comm property mirroring whether the outworlder currently has a `CombatSession`
	on the server. Public — see `HealthProperty`.
]=]

--[=[
	@prop RenderedEquipmentChanged Signal<EquipmentSlot, Model?>
	@within OutworlderClient
	Fires when a slot's rendered Model attaches (with the Model) or detaches
	(with `nil`). Pair with `GetRenderedModel` for the current value. Public:
	external systems (e.g. `FishingSpotClient` for the fishing-line rope clones)
	subscribe to react to remote players' equipment changes.
]=]

--[=[
	@prop InActionProperty any
	@within OutworlderClient
	Comm property mirroring whether the outworlder is currently executing an
	`Action` on the server (mining, woodcutting, etc.). Public — see
	`HealthProperty`. `ActionPromptClient` consumes this to hide ActionPrompts
	in the world while the local player is mid-action.
]=]

type SlotState = {
	Trove: any,
	ItemKind: string,
	Model: Model?, -- The currently rendered, character-parented model. Populated after the asset download resolves; `nil` before then.
}

function OutworlderClient:Construct()
	self.Trove = Trove.new()
	self.SlotStates = {} :: { [string]: SlotState }

	self.Player = Players:GetPlayerFromCharacter(self.Instance)
	self.IsLocalPlayer = self.Player == Players.LocalPlayer

	self.MaxStamina = MovementTypes.MaxStamina
	self.MaxStaminaChanged = self.Trove:Construct(Signal) :: Signal.Signal<number>
	self.Stamina = self.MaxStamina
	self.StaminaChanged = self.Trove:Construct(Signal) :: Signal.Signal<number>
	self.ActionProgress = nil :: ActionProgress?
	self.ActionProgressChanged = self.Trove:Construct(Signal) :: Signal.Signal<ActionProgress?>
	self.RenderedEquipmentChanged = self.Trove:Construct(Signal) :: Signal.Signal<EquipmentSlot, Model?>
	self.WasMoving = false
	self.FaceTowardsLoopTrove = nil :: any

	self.LastReplicatedHealth = nil :: number?
	self.LastDamagedAt = nil :: number?
	self.BillboardKey = `Outworlder:{HttpService:GenerateGUID(false)}`
	self.BillboardActive = false
	self.ExpireThread = nil :: thread?

	self.Comm = Comm.ClientComm.new(self.Instance, false, "Outworlder")
	self.Trove:Add(self.Comm)
	self.EquipmentProperty = self.Comm:GetProperty("Equipment")
	self.MovementModeProperty = self.Comm:GetProperty("MovementMode")
	self.MaxStaminaProperty = self.Comm:GetProperty("MaxStamina")
	self.StaminaProperty = self.Comm:GetProperty("Stamina")
	self.MaxHealthProperty = self.Comm:GetProperty("MaxHealth")
	self.HealthProperty = self.Comm:GetProperty("Health")
	self.InCombatProperty = self.Comm:GetProperty("InCombat")
	self.InActionProperty = self.Comm:GetProperty("InAction")
	self.ActionProgressProperty = self.Comm:GetProperty("ActionProgress")
	self.ActionFailedSignal = self.Comm:GetSignal("ActionFailed")
	self.FaceTowardsSignal = self.Comm:GetSignal("FaceTowards")
	self.RequestSetMovementModeFunction = self.Comm:GetFunction("RequestSetMovementMode")
end

--[=[
	Updates the predicted stamina and fires `StaminaChanged` if the value actually changed.
	@within OutworlderClient
	@param value number
]=]
function OutworlderClient:SetStamina(value: number)
	if self.Stamina == value then
		return
	end
	self.Stamina = value
	self.StaminaChanged:Fire(value)
end

--[=[
	Updates the replicated max stamina and fires `MaxStaminaChanged` if the value changed.
	@within OutworlderClient
	@param value number
]=]
function OutworlderClient:SetMaxStamina(value: number)
	if self.MaxStamina == value then
		return
	end
	self.MaxStamina = value
	self.MaxStaminaChanged:Fire(value)
end

--[=[
	`HealthProperty` observer. The first replication just seeds
	`LastReplicatedHealth`; subsequent decreases stamp `LastDamagedAt` and
	refresh billboard visibility. The component does not cache `Health` —
	consumers should read `HealthProperty:Get()` / subscribe via
	`Observing.observeCommProperty(HealthProperty, ...)` directly.
	@within OutworlderClient
	@param value number
]=]
function OutworlderClient:HandleHealth(value: number)
	local previous = self.LastReplicatedHealth
	self.LastReplicatedHealth = value
	if previous ~= nil and value < previous then
		self.LastDamagedAt = os.clock()
		self:RefreshBillboardVisibility()
	end
end

function OutworlderClient:Start()
	self.ControllerManager =
		self.Instance:WaitForChild("ControllerManager", WAIT_FOR_CHILD_TIMEOUT) :: ControllerManager
	assert(
		self.ControllerManager ~= nil,
		`OutworlderClient: {self.Instance:GetFullName()} has no ControllerManager (is the Character Controller Library enabled?)`
	)

	self.Trove:Add(Observing.observeCommProperty(self.EquipmentProperty, function(equipment: Equipment)
		self:ReconcileEquipment(equipment)
	end))

	self.Trove:Add(Observing.observeCommProperty(self.HealthProperty, function(value: number)
		self:HandleHealth(value)
	end))

	self.Trove:Add(Observing.observeCommProperty(self.InCombatProperty, function(_value: boolean)
		self:RefreshBillboardVisibility()
	end))

	if self.IsLocalPlayer then
		self:SetupLocalControls()
	end
end

function OutworlderClient:Stop()
	if self.ExpireThread ~= nil then
		task.cancel(self.ExpireThread)
		self.ExpireThread = nil
	end
	if self.BillboardActive then
		Billboards.Remove(self.BillboardKey)
		self.BillboardActive = false
	end
	self.Trove:Destroy()
end

--[=[
	Recomputes whether the overhead health bar should be visible and
	(un)registers a `Billboards` entry accordingly. Visible whenever the
	character is in combat or has taken damage within
	`BAR_VISIBILITY_SECONDS`. Schedules a delayed re-check when visibility
	hangs on a damage-tail timeout.
	@within OutworlderClient
]=]
function OutworlderClient:RefreshBillboardVisibility()
	local now = os.clock()
	local inCombat = self.InCombatProperty:Get() :: boolean
	local damagedRecently = self.LastDamagedAt ~= nil and (now - self.LastDamagedAt) < BAR_VISIBILITY_SECONDS
	local shouldShow = inCombat or damagedRecently

	if shouldShow then
		if not self.BillboardActive then
			self:RegisterBillboard()
		end
		if self.ExpireThread ~= nil then
			task.cancel(self.ExpireThread)
			self.ExpireThread = nil
		end
		if not inCombat and self.LastDamagedAt ~= nil then
			local remaining = BAR_VISIBILITY_SECONDS - (now - self.LastDamagedAt)
			self.ExpireThread = task.delay(remaining, function()
				self.ExpireThread = nil
				self:RefreshBillboardVisibility()
			end)
		end
	else
		if self.BillboardActive then
			Billboards.Remove(self.BillboardKey)
			self.BillboardActive = false
		end
		if self.ExpireThread ~= nil then
			task.cancel(self.ExpireThread)
			self.ExpireThread = nil
		end
	end
end

--[=[
	Adds the overhead health bar billboard entry. Adornee resolves to the
	character's `Head` when present, falling back to `HumanoidRootPart`.
	@within OutworlderClient
]=]
function OutworlderClient:RegisterBillboard()
	local adornee = self.Instance:FindFirstChild("Head") :: BasePart?
	if adornee == nil then
		adornee = self.Instance:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if adornee == nil then
		return
	end
	Billboards.Set(self.BillboardKey, {
		Adornee = adornee,
		Native = {
			Size = UDim2.fromScale(4, 0.2),
			StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
		},
		Render = function()
			return e(CombatantBillboard, {
				HealthProperty = self.HealthProperty,
				MaxHealthProperty = self.MaxHealthProperty,
			})
		end,
	})
	self.BillboardActive = true
end

--[=[
	Wires keyboard input + the heartbeat-driven "stopped moving" sprint cancel for the
	local player. Only invoked when this Outworlder belongs to `Players.LocalPlayer`.
	@within OutworlderClient
	@private
]=]
function OutworlderClient:SetupLocalControls()
	self.Trove:Add(Observing.observeCommProperty(self.MaxStaminaProperty, function(value: number)
		self:SetMaxStamina(value)
	end))

	self.Trove:Add(Observing.observeCommProperty(self.StaminaProperty, function(stamina: number)
		self:SetStamina(stamina)
	end))

	self.Trove:Add(Observing.observeCommProperty(self.ActionProgressProperty, function(progress: ActionProgress?)
		self.ActionProgress = progress
		self.ActionProgressChanged:Fire(progress)
	end))

	self.Trove:Add(self.FaceTowardsSignal:Connect(function(target: AbilityTypes.FaceTarget, duration: number?)
		self:ApplyFaceTowards(target, duration)
	end))

	self.Trove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		self:HandleInput(input)
	end)

	self.Trove:Connect(RunService.Heartbeat, function(dt: number)
		self:SprintTick(dt)
	end)
end

--[=[
	Pivots the local character to face `target` on the horizontal plane. Driven
	by the `FaceTowards` Comm signal from the server-side `Outworlder`, which
	delegates orientation to us to avoid mid-movement snap-backs against the
	client's position prediction.

	`target` is resolved via `AbilityTypes.ResolveFaceTarget` (see that module for accepted
	input shapes). With `duration == nil`, snaps once via `PivotTo`. With a
	duration, disables `Humanoid.AutoRotate` and drives
	`ControllerManager.FacingDirection` toward the target every Heartbeat for
	`duration` seconds — re-resolving dynamic targets each frame so the
	activator tracks movement — then restores `AutoRotate`. A second call while
	a loop is already running cancels the previous one in favor of the new
	request.
	@within OutworlderClient
	@param target AbilityTypes.FaceTarget
	@param duration number?
]=]
function OutworlderClient:ApplyFaceTowards(target: AbilityTypes.FaceTarget, duration: number?)
	local primary = self.Instance.PrimaryPart
	if primary == nil then
		return
	end

	local position = AbilityTypes.ResolveFaceTarget(target)
	local delta = (position - primary.Position) * Vector3.new(1, 0, 1)
	if not delta:FuzzyEq(Vector3.zero) then
		self.Instance:PivotTo(CFrame.lookAlong(primary.Position, delta))
	end

	if duration == nil then
		return
	end

	if self.FaceTowardsLoopTrove ~= nil then
		self.Trove:Remove(self.FaceTowardsLoopTrove)
	end
	local loopTrove = self.Trove:Extend()
	self.FaceTowardsLoopTrove = loopTrove

	local humanoid = self.Instance:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid ~= nil then
		local wasAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		loopTrove:Add(function()
			humanoid.AutoRotate = wasAutoRotate
		end)
	end

	loopTrove:Add(function()
		if self.FaceTowardsLoopTrove == loopTrove then
			self.FaceTowardsLoopTrove = nil
		end
	end)

	loopTrove:Connect(RunService.Heartbeat, function()
		local framePosition = AbilityTypes.ResolveFaceTarget(target)
		local frameDelta = (framePosition - primary.Position) * Vector3.new(1, 0, 1)
		if frameDelta:FuzzyEq(Vector3.zero) then
			return
		end
		self.ControllerManager.FacingDirection = frameDelta.Unit
	end)

	loopTrove:Add(task.delay(duration, function()
		if self.FaceTowardsLoopTrove == loopTrove then
			self.Trove:Remove(loopTrove)
		end
	end))
end

--[=[
	Routes a single `InputBegan` to the appropriate toggle. Kept as a switch (rather than
	inline `Connect` lambdas) so future mobile button handlers can call the toggle methods
	directly without going through `UserInputService`.
	@within OutworlderClient
	@param input InputObject
]=]
function OutworlderClient:HandleInput(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		self:ToggleSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		self:ToggleCrouch()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		self:TryFirePrimaryAbility()
	end
end

--[=[
	Looks up the primary ability of the player's currently equipped main-hand
	item, if any, and asks the server to activate it. Server is authoritative
	for cooldown/cost/requirements; this is fire-and-forget from the client.
	No-op when no equipped item exposes a `PrimaryAbility`.
	@within OutworlderClient
]=]
function OutworlderClient:TryFirePrimaryAbility()
	local equipment = self.EquipmentProperty:Get() :: Equipment
	local item = equipment.MainHandMelee
	if item == nil then
		return
	end
	local def = ItemDefs[item.Kind]
	if def == nil or def.PrimaryAbility == nil then
		return
	end
	AbilityClient.Activate(def.PrimaryAbility)
end

--[=[
	Triggers a jump on the local character. Client-authoritative: we trust the
	player here so mobile/touch jumps feel responsive without a roundtrip. No-op
	when airborne so jump can't be used to double-jump.

	Drives the jump by writing `AssemblyLinearVelocity.Y` on the ControllerManager's
	root part rather than `Humanoid:ChangeState(Jumping)`, because the Character
	Controller Library bypasses the Humanoid state machine — `ChangeState` is a
	no-op while `ControllerManager` is the one driving locomotion. Horizontal
	velocity is preserved so the character keeps its current run momentum.
	@within OutworlderClient
]=]
function OutworlderClient:Jump()
	if not OutworlderShared.IsGrounded(self.ControllerManager) then
		return
	end
	local rootPart = self.ControllerManager.RootPart
	if rootPart == nil then
		return
	end
	local current = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(current.X, MovementTypes.JumpVelocity, current.Z)
end

--[=[
	Returns whether the sprint input is currently held. Wraps the keyboard check so a
	future mobile sprint button can OR its state in here without touching the rest of
	the sprint logic.
	@within OutworlderClient
	@return boolean
]=]
function OutworlderClient:IsSprintInputDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
end

--[=[
	Toggles between Sprint and Walk based on the currently-replicated mode.
	@within OutworlderClient
]=]
function OutworlderClient:ToggleSprint()
	local current = self.MovementModeProperty:Get()
	if current ~= "Sprint" and self.Stamina <= 0 then
		return
	end
	local desired: MovementMode = if current == "Sprint" then "Walk" else "Sprint"
	self:SetMovementMode(desired)
end

--[=[
	Toggles between Crouch and Walk based on the currently-replicated mode.
	@within OutworlderClient
]=]
function OutworlderClient:ToggleCrouch()
	local current = self.MovementModeProperty:Get()
	local desired: MovementMode = if current == "Crouch" then "Walk" else "Crouch"
	self:SetMovementMode(desired)
end

--[=[
	Optimistically applies `mode` to the local ControllerManager, then asks the server to
	make the change authoritative. If the server rejects, falls back to whatever mode the
	`MovementMode` property currently advertises.
	@within OutworlderClient
	@param mode MovementMode
]=]
function OutworlderClient:SetMovementMode(mode: MovementMode)
	OutworlderShared.ApplyMode(self.ControllerManager, mode)

	task.spawn(function()
		local accepted = self.RequestSetMovementModeFunction(mode)
		if accepted then
			return
		end
		local authoritative = self.MovementModeProperty:Get() :: MovementMode
		OutworlderShared.ApplyMode(self.ControllerManager, authoritative)
	end)
end

--[=[
	Per-frame tick that handles three things:

	1. Movement-start sprint trigger: on the frame `MovingDirection` transitions from
	   zero to non-zero, if the player is holding `LeftShift` (and has stamina), enter
	   Sprint. This makes "hold shift, then start moving" feel like sprint-on-press
	   without needing a separate "intent" flag.
	2. Sprint cancel on stop: while in Sprint, `MovingDirection == 0` requests Walk.
	3. Predictive stamina drain via `OutworlderShared.StepStaminaDrain` (regen is
	   server-only, so the client only simulates drain and waits for replication
	   to learn about regen). If stamina hits zero, requests Walk immediately so
	   the player feels the slowdown without a roundtrip.

	Server replication of `Stamina` will hard-snap our value to the authoritative one
	via the `observeCommProperty` subscription set up in `SetupLocalControls`.
	@within OutworlderClient
	@param dt number
]=]
function OutworlderClient:SprintTick(dt: number)
	local isMoving = OutworlderShared.IsMoving(self.ControllerManager)
	local mode = self.MovementModeProperty:Get() :: MovementMode

	if isMoving and not self.WasMoving and mode ~= "Sprint" and self.Stamina > 0 and self:IsSprintInputDown() then
		self:SetMovementMode("Sprint")
		mode = "Sprint"
	end
	self.WasMoving = isMoving

	if mode ~= "Sprint" then
		return
	end

	if not isMoving then
		self:SetMovementMode("Walk")
		return
	end

	self:SetStamina(OutworlderShared.StepStaminaDrain(self.Stamina, mode, isMoving, dt))
	if self.Stamina <= 0 then
		self:SetMovementMode("Walk")
	end
end

--[=[
	Updates rendered slots so they match `equipment`. Slots whose kind is unchanged are
	left alone; changed slots have their previous render torn down and a fresh fetch
	dispatched. Removing the slot's sub-trove cancels any in-flight download chain, so
	late-arriving assets are never created or attached.
	@within OutworlderClient
	@param equipment Equipment
]=]
function OutworlderClient:ReconcileEquipment(equipment: Equipment)
	for _, slotKey in EquipmentTypes.Slots do
		local newItem = equipment[slotKey]
		local newKind = if newItem ~= nil then newItem.Kind else nil

		local state = self.SlotStates[slotKey]
		local oldKind = if state ~= nil then state.ItemKind else nil

		if newKind == oldKind then
			continue
		end

		if state ~= nil then
			self.Trove:Remove(state.Trove)
			self.SlotStates[slotKey] = nil
			if state.Model ~= nil then
				self.RenderedEquipmentChanged:Fire(slotKey, nil)
			end
		end

		if newItem ~= nil then
			self:RenderSlot(slotKey, newItem)
		end
	end
end

--[=[
	Dispatches the asset download for `slotKey`'s `item` and, on resolution, hands the
	clone to the slot's renderer. The download promise is tracked by `slotTrove`, so a
	mid-flight equipment change cancels the chain before the clone is made or attached.
	@within OutworlderClient
	@param slotKey EquipmentSlot
	@param item Item
]=]
function OutworlderClient:RenderSlot(slotKey: EquipmentSlot, item: Item)
	local renderer = SlotRenderers[slotKey]
	if renderer == nil then
		return
	end

	local def = ItemDefs[item.Kind]
	if def == nil or def.AssetPath == nil then
		return
	end

	local slotTrove = self.Trove:Extend()
	local state: SlotState = { Trove = slotTrove, ItemKind = item.Kind, Model = nil }
	self.SlotStates[slotKey] = state

	slotTrove:AddPromise(DownloadClient.Download(def.AssetPath)
		:andThen(function(asset: Instance)
			slotTrove:Add(asset)
			renderer(asset, self.Instance, slotTrove)
			-- The renderer's contract is to parent `asset` under the character.
			-- Capture and announce only if the slot state we set above is still
			-- the live one (an in-flight equipment swap could have replaced it).
			if self.SlotStates[slotKey] == state and asset:IsA("Model") then
				state.Model = asset
				self.RenderedEquipmentChanged:Fire(slotKey, asset)
			end
		end)
		:catch(function(err)
			warn(`OutworlderClient: failed to render {slotKey} ({item.Kind}): {err}`)
		end))
end

--[=[
	Returns the currently rendered Model for `slot`, or `nil` if the slot is
	empty or the asset hasn't finished downloading yet. Subscribe to
	`RenderedEquipmentChanged` for change notifications.
	@within OutworlderClient
	@param slot EquipmentSlot
	@return Model?
]=]
function OutworlderClient:GetRenderedModel(slot: EquipmentSlot): Model?
	local state = self.SlotStates[slot]
	if state == nil then
		return nil
	end
	return state.Model
end

return OutworlderClient
