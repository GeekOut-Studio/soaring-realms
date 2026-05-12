--!strict

--[=[
	@class PlayerDataTypes
	Shared type and default template for player persistent data.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local HotbarTypes = require(ReplicatedStorage.Shared.Types.HotbarTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

--[=[
	@interface PlayerData
	@within PlayerDataTypes
	@field Inventory Inventory
	@field Equipment Equipment
	@field Skills Skills
	@field Hotbar Hotbar
]=]
export type PlayerData = {
	Inventory: InventoryTypes.Inventory,
	Equipment: EquipmentTypes.Equipment,
	Skills: SkillTypes.Skills,
	Hotbar: HotbarTypes.Hotbar,
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
	Skills = SkillTypes.DefaultSkills,
	Hotbar = HotbarTypes.DefaultHotbar,
} :: PlayerData)

return PlayerDataTypes
