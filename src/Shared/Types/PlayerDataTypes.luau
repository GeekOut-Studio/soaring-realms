--!strict

--[=[
	@class PlayerDataTypes
	Shared type and default template for player persistent data.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

--[=[
	@interface PlayerData
	@within PlayerDataTypes
	@field Inventory Inventory
	@field Equipment Equipment
	@field Skills {}
]=]
export type PlayerData = {
	Inventory: InventoryTypes.Inventory,
	Equipment: EquipmentTypes.Equipment,
	Skills: {},
}

local PlayerDataTypes = {}

--[=[
	@prop Template PlayerData
	@within PlayerDataTypes
	Default value used to initialize a new player's data.
]=]
PlayerDataTypes.Template = table.freeze({
	Inventory = InventoryTypes.DefaultInventory,
	Equipment = EquipmentTypes.DefaultEquipment,
	Skills = {},
} :: PlayerData)

return PlayerDataTypes
