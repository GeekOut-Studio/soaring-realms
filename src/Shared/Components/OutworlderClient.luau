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
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)

local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)
local Observing = require(ReplicatedStorage.Shared.Observing)
local OutworlderShared = require(ReplicatedStorage.Shared.Components.OutworlderShared)

type EquipmentSlot = EquipmentTypes.EquipmentSlot
type Equipment = EquipmentTypes.Equipment
type Item = InventoryTypes.Item
type MovementMode = MovementTypes.MovementMode

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

type SlotState = {
	Trove: any,
	ItemKind: string,
}

function OutworlderClient:Construct()
	self.Trove = Trove.new()
	self.SlotStates = {} :: { [string]: SlotState }

	self.Player = Players:GetPlayerFromCharacter(self.Instance)
	self.IsLocalPlayer = self.Player == Players.LocalPlayer

	self.Stamina = MovementTypes.MaxStamina
	self.StaminaChanged = self.Trove:Construct(Signal) :: Signal.Signal<number>
	self.WasMoving = false

	self.Comm = Comm.ClientComm.new(self.Instance, false, "Outworlder")
	self.Trove:Add(self.Comm)
	self.EquipmentProperty = self.Comm:GetProperty("Equipment")
	self.MovementModeProperty = self.Comm:GetProperty("MovementMode")
	self.StaminaProperty = self.Comm:GetProperty("Stamina")
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

	if self.IsLocalPlayer then
		self:SetupLocalControls()
	end
end

function OutworlderClient:Stop()
	self.Trove:Destroy()
end

--[=[
	Wires keyboard input + the heartbeat-driven "stopped moving" sprint cancel for the
	local player. Only invoked when this Outworlder belongs to `Players.LocalPlayer`.
	@within OutworlderClient
	@private
]=]
function OutworlderClient:SetupLocalControls()
	self.Trove:Add(Observing.observeCommProperty(self.StaminaProperty, function(stamina: number)
		self:SetStamina(stamina)
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
	end
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
	self.SlotStates[slotKey] = { Trove = slotTrove, ItemKind = item.Kind }

	slotTrove:AddPromise(DownloadClient.Download(def.AssetPath)
		:andThen(function(asset: Instance)
			slotTrove:Add(asset)
			renderer(asset, self.Instance, slotTrove)
		end)
		:catch(function(err)
			warn(`OutworlderClient: failed to render {slotKey} ({item.Kind}): {err}`)
		end))
end

return OutworlderClient
