--[=[
	@class EquipmentClient
	Client-side interface for the local player's equipment. Reflects the server-driven `Equipment` Comm property.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)

type Equipment = EquipmentTypes.Equipment

local EquipmentClient = {}

local equipmentProperty
local equipFunction
local unequipFunction

function EquipmentClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Equipment")
	equipmentProperty = clientComm:GetProperty("Equipment")
	equipFunction = clientComm:GetFunction("Equip")
	unequipFunction = clientComm:GetFunction("Unequip")
end

--[=[
	Returns the local player's current equipment.
	@within EquipmentClient
	@return Equipment
]=]
function EquipmentClient.Get(): Equipment
	return equipmentProperty:Get()
end

--[=[
	Observes changes to the local player's equipment.

	`callback` is called immediately with the current value and again on every change.
	It may return a cleanup function that is called before the next invocation and on disconnect.
	@within EquipmentClient
	@param callback (equipment: Equipment) -> (() -> ())? -- Handler; may return a cleanup.
	@return () -> () -- Disconnects the observer when called.
]=]
function EquipmentClient.ObserveEquipment(callback: (equipment: Equipment) -> (() -> ())?)
	return Observing.observeCommProperty(equipmentProperty, callback)
end

--[=[
	Requests the server to equip the item in `inventorySlot` into `equipmentSlot`.
	@within EquipmentClient
	@param inventorySlot string
	@param equipmentSlot EquipmentSlot
]=]
function EquipmentClient.Equip(inventorySlot: string, equipmentSlot: EquipmentTypes.EquipmentSlot)
	equipFunction(inventorySlot, equipmentSlot)
end

--[=[
	Requests the server to unequip the item in `equipmentSlot` back into the inventory.
	@within EquipmentClient
	@param equipmentSlot EquipmentSlot
]=]
function EquipmentClient.Unequip(equipmentSlot: EquipmentTypes.EquipmentSlot)
	unequipFunction(equipmentSlot)
end

return EquipmentClient
