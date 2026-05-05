--!strict

--[=[
	@class RequirementsTypes
	Type contracts for the requirements system. A `Requirement` is a tagged record
	that knows how to check itself against a `PlayerSnapshot` (a unified view of
	skills + inventory + equipment). Both server-authoritative checks
	(`RequirementsServer.CheckForPlayer`) and client-predictive checks
	(`RequirementsClient.CheckForLocal`) build a snapshot from the appropriate
	state source and run the same `Check` algorithm against it.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

--[=[
	@interface PlayerSnapshot
	@within RequirementsTypes
	@field Skills SkillTypes.Skills
	@field Inventory InventoryTypes.Inventory
	@field Equipment EquipmentTypes.Equipment
]=]
export type PlayerSnapshot = {
	Skills: SkillTypes.Skills,
	Inventory: InventoryTypes.Inventory,
	Equipment: EquipmentTypes.Equipment,
}

--[=[
	@interface Requirement
	@within RequirementsTypes
	@field Kind string -- Tag identifying the requirement variety.
	@field Check (snapshot: PlayerSnapshot) -> (boolean, string?) -- Returns `(true, nil)` when satisfied or `(false, message)` when not.
]=]
export type Requirement = {
	Kind: string,
	Check: (snapshot: PlayerSnapshot) -> (boolean, string?),
}

return {}
