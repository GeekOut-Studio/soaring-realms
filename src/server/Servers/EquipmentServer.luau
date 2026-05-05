--!strict

--[=[
	@class EquipmentServer
	Manages player equipment: equipping items from the inventory and unequipping
	them back into it. Equip/unequip operations atomically update both the
	`Inventory` and `Equipment` tables through a single `DataServer.UpdateData`
	call.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require(ReplicatedStorage.Packages.Signal)
local t = require(ReplicatedStorage.Packages.t)

local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Item = InventoryTypes.Item
type Inventory = InventoryTypes.Inventory
type Equipment = EquipmentTypes.Equipment

local EquipmentServer = {}

local equipmentProperty
local equipmentChanged: Signal.Signal<Player, Equipment> = Signal.new()

-- Private helpers

local function asInventory(data: any): Inventory
	return (data.Inventory :: any) :: Inventory
end

local function asEquipment(data: any): Equipment
	return (data.Equipment :: any) :: Equipment
end

local function findFreeInventorySlot(inventory: Inventory): string?
	for i = 1, InventoryTypes.Size do
		local key = tostring(i)
		if inventory[key] == nil then
			return key
		end
	end
	return nil
end

local function canEquipTo(item: Item, equipmentSlot: string): boolean
	local def = ItemDefs[item.Kind]
	if def == nil or def.EquipSlots == nil then
		return false
	end
	for _, allowed in def.EquipSlots do
		if allowed == equipmentSlot then
			return true
		end
	end
	return false
end

-- Commits an atomic update to both Inventory and Equipment, then replicates
-- each via Comm. Callers MUST have verified the player's data is loaded.
local function commit(player: Player, newInventory: Inventory, newEquipment: Equipment)
	local committed = DataServer.UpdateData(player, function(data)
		return Sift.Dictionary.merge(data, {
			Inventory = newInventory,
			Equipment = newEquipment,
		})
	end)
	assert(committed ~= nil, "EquipmentServer.commit: caller must verify DataServer.IsLoaded(player) first")
	InventoryServer.ReplicateInventory(player, newInventory)
	equipmentProperty:SetFor(player, newEquipment)
	equipmentChanged:Fire(player, newEquipment)
end

--[=[
	Returns a shallow copy of the player's current equipment. If the player's
	data isn't loaded, returns a copy of the default (empty) equipment — callers
	never receive nil and never crash.
	@within EquipmentServer
	@param player Player
	@return Equipment
]=]
function EquipmentServer.GetEquipment(player: Player): Equipment
	local data = DataServer.GetData(player)
	if data == nil then
		return Sift.Dictionary.copy(EquipmentTypes.DefaultEquipment)
	end
	return Sift.Dictionary.copy(asEquipment(data))
end

--[=[
	Observes changes to `player`'s equipment.

	`callback` is invoked once with the current value immediately (the default
	empty equipment if the player's data isn't loaded yet) and again on every
	subsequent equip/unequip commit. The data-loaded path also fires
	`equipmentChanged`, so observers that subscribed before the player's data
	was loaded receive the loaded value at that time.
	@within EquipmentServer
	@param player Player
	@param callback (equipment: Equipment) -> () -- Handler called on each value change.
	@return () -> () -- Disconnects the observer when called.
]=]
function EquipmentServer.ObserveEquipment(player: Player, callback: (equipment: Equipment) -> ()): () -> ()
	local connection = equipmentChanged:Connect(function(p: Player, equipment: Equipment)
		if p == player then
			callback(equipment)
		end
	end)

	callback(EquipmentServer.GetEquipment(player))

	return function()
		connection:Disconnect()
	end
end

--[=[
	Equips the item in `inventorySlot` to `equipmentSlot`.

	The item's def must list `equipmentSlot` in its `EquipSlots`. If `equipmentSlot`
	is already occupied, the previously equipped item is swapped back into
	`inventorySlot`.
	@within EquipmentServer
	@param player Player
	@param inventorySlot string -- The inventory slot holding the item to equip.
	@param equipmentSlot EquipmentSlot -- The equipment slot to place the item into.
	@return boolean -- `false` when the inventory slot is empty or the item is not
		equippable into `equipmentSlot`.
]=]
function EquipmentServer.Equip(player: Player, inventorySlot: string, equipmentSlot: string): boolean
	assert(EquipmentTypes.SlotSet[equipmentSlot], `EquipmentServer.Equip: unknown equipment slot {equipmentSlot}`)

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = asInventory(data)
	local equipment: Equipment = asEquipment(data)

	local item = inventory[inventorySlot]
	if item == nil then
		return false
	end

	if not canEquipTo(item, equipmentSlot) then
		return false
	end

	local newInventory: Inventory = Sift.Dictionary.copy(inventory)
	local newEquipment: Equipment = Sift.Dictionary.copy(equipment)

	local existing = equipment[equipmentSlot]
	newEquipment[equipmentSlot] = item
	newInventory[inventorySlot] = existing

	commit(player, newInventory, newEquipment)
	return true
end

--[=[
	Unequips the item in `equipmentSlot` back into the first free inventory slot.

	No-op if the equipment slot is empty or the inventory has no free slots.
	@within EquipmentServer
	@param player Player
	@param equipmentSlot EquipmentSlot -- The equipment slot to unequip from.
	@return boolean -- `false` when the slot is empty or the inventory is full.
]=]
function EquipmentServer.Unequip(player: Player, equipmentSlot: string): boolean
	assert(EquipmentTypes.SlotSet[equipmentSlot], `EquipmentServer.Unequip: unknown equipment slot {equipmentSlot}`)

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = asInventory(data)
	local equipment: Equipment = asEquipment(data)

	local item = equipment[equipmentSlot]
	if item == nil then
		return false
	end

	local freeSlot = findFreeInventorySlot(inventory)
	if freeSlot == nil then
		return false
	end

	local newInventory: Inventory = Sift.Dictionary.copy(inventory)
	local newEquipment: Equipment = Sift.Dictionary.copy(equipment)

	newInventory[freeSlot] = item
	newEquipment[equipmentSlot] = nil

	commit(player, newInventory, newEquipment)
	return true
end

function EquipmentServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Equipment")
	equipmentProperty = serverComm:CreateProperty("Equipment", EquipmentTypes.DefaultEquipment)

	serverComm:BindFunction("Equip", function(player, inventorySlot, equipmentSlot)
		if not t.string(inventorySlot) then
			return
		end
		if not t.string(equipmentSlot) then
			return
		end

		return EquipmentServer.Equip(player, inventorySlot, equipmentSlot)
	end)

	serverComm:BindFunction("Unequip", function(player, equipmentSlot)
		if not t.string(equipmentSlot) then
			return
		end

		return EquipmentServer.Unequip(player, equipmentSlot)
	end)

	DataServer.ObservePlayer(function(player, data)
		local equipment = asEquipment(data)
		equipmentProperty:SetFor(player, equipment)
		equipmentChanged:Fire(player, equipment)
		return nil
	end)
end

return EquipmentServer
