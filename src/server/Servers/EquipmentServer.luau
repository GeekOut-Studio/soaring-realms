--!strict

--[=[
	@class EquipmentServer
	Manages player equipment: equipping items from the inventory and unequipping them back into it.
	Equip and unequip operations atomically update both the `Inventory` and `Equipment` tables
	through a single `DataServer.UpdateData` call.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observers = require(ReplicatedStorage.Packages.Observers)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)
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

-- Commits an atomic update to both Inventory and Equipment, then replicates each via Comm.
local function commit(player: Player, newInventory: Inventory, newEquipment: Equipment)
	return DataServer.UpdateData(player, function(data)
		return Sift.Dictionary.merge(data, {
			Inventory = newInventory,
			Equipment = newEquipment,
		})
	end):andThen(function()
		InventoryServer.ReplicateInventory(player, newInventory)
		equipmentProperty:SetFor(player, newEquipment)
		return true
	end)
end

--[=[
	Returns a shallow copy of the player's current equipment.
	@within EquipmentServer
	@param player Player
	@return Promise<Equipment>
]=]
function EquipmentServer.GetEquipment(player: Player): any
	return DataServer.GetData(player):andThen(function(data)
		return Sift.Dictionary.copy(asEquipment(data))
	end)
end

--[=[
	Equips the item in `inventorySlot` to `equipmentSlot`.

	The item's def must list `equipmentSlot` in its `EquipSlots`. If `equipmentSlot` is already
	occupied, the previously equipped item is swapped back into `inventorySlot`.
	@within EquipmentServer
	@param player Player
	@param inventorySlot string -- The inventory slot holding the item to equip.
	@param equipmentSlot EquipmentSlot -- The equipment slot to place the item into.
	@return Promise<boolean> -- Resolves `false` when the inventory slot is empty or the item
		is not equippable into `equipmentSlot`.
]=]
function EquipmentServer.Equip(player: Player, inventorySlot: string, equipmentSlot: string): any
	if not EquipmentTypes.SlotSet[equipmentSlot] then
		return Promise.reject("Unknown equipment slot: " .. equipmentSlot)
	end

	return DataServer.GetData(player):andThen(function(data)
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

		return commit(player, newInventory, newEquipment)
	end)
end

--[=[
	Unequips the item in `equipmentSlot` back into the first free inventory slot.

	No-op if the equipment slot is empty or the inventory has no free slots.
	@within EquipmentServer
	@param player Player
	@param equipmentSlot EquipmentSlot -- The equipment slot to unequip from.
	@return Promise<boolean> -- Resolves `false` when the slot is empty or the inventory is full.
]=]
function EquipmentServer.Unequip(player: Player, equipmentSlot: string): any
	if not EquipmentTypes.SlotSet[equipmentSlot] then
		return Promise.reject("Unknown equipment slot: " .. equipmentSlot)
	end

	return DataServer.GetData(player):andThen(function(data)
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

		return commit(player, newInventory, newEquipment)
	end)
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

	Observers.observePlayer(function(player)
		EquipmentServer.GetEquipment(player):andThen(function(equipment)
			equipmentProperty:SetFor(player, equipment)
		end)

		return nil
	end)
end

return EquipmentServer
