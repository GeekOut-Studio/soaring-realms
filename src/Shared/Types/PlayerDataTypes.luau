--!strict

--[=[
	@class PlayerDataTypes
	Shared type and default template for player persistent data.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

--[=[
	@interface PlayerData
	@within PlayerDataTypes
	@field Inventory Inventory
	@field Skills {}
]=]
export type PlayerData = {
	Inventory: InventoryTypes.Inventory,
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
	Skills = {},
} :: PlayerData)

return PlayerDataTypes
