--[=[
	@class OutworlderClient
	@client
	Renders each Outworlder's equipped gear on its character. Subscribes to the per-instance
	`Equipment` Comm property published by the server-side `Outworlder` and reconciles a
	per-slot rendered asset whenever the equipped item kind changes.

	Runs on every client for every Outworlder (including the local player). Slot-specific
	attachment behavior is registered in `SlotRenderers`; slots without a renderer are skipped.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local Observing = require(ReplicatedStorage.Shared.Observing)

type EquipmentSlot = EquipmentTypes.EquipmentSlot
type Equipment = EquipmentTypes.Equipment
type Item = InventoryTypes.Item

local LIMB_WAIT_TIMEOUT = 10

local SlotRenderers: { [string]: (asset: Instance, character: Model, trove: any) -> () } = {
	MainHandMelee = function(asset, character, trove)
		local rightHand = character:WaitForChild("RightHand", LIMB_WAIT_TIMEOUT) :: BasePart
		assert(rightHand ~= nil, `OutworlderClient: {character:GetFullName()} has no RightHand`)

		local charAttachment = rightHand:WaitForChild("RightGripAttachment", LIMB_WAIT_TIMEOUT) :: Attachment
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

	self.Comm = Comm.ClientComm.new(self.Instance, false, "Outworlder")
	self.Trove:Add(self.Comm)
	self.EquipmentProperty = self.Comm:GetProperty("Equipment")
end

function OutworlderClient:Start()
	self.Trove:Add(Observing.observeCommProperty(self.EquipmentProperty, function(equipment: Equipment)
		self:Reconcile(equipment)
	end))
end

function OutworlderClient:Stop()
	self.Trove:Destroy()
end

--[=[
	Updates rendered slots so they match `equipment`. Slots whose kind is unchanged are
	left alone; changed slots have their previous render torn down and a fresh fetch
	dispatched. Removing the slot's sub-trove cancels any in-flight download chain, so
	late-arriving assets are never created or attached.
	@within OutworlderClient
	@param equipment Equipment
]=]
function OutworlderClient:Reconcile(equipment: Equipment)
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
