--!strict

--[=[
	@class Requirements
	Pure-function check + constructor namespace for the requirements system.
	Domain-agnostic: any feature (action, station, prompt) that needs gating on
	player state composes a list of `Requirement` records using the constructors
	exported here, then runs `Requirements.Check(snapshot, requirements)` to find
	the first failure.

	Use `RequirementsServer.CheckForPlayer` (server) or
	`RequirementsClient.CheckForLocal` (client) to obtain a `PlayerSnapshot`
	automatically.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Equipped = require(ReplicatedStorage.Shared.Requirements.Equipped)
local InventoryHasRoomFor = require(ReplicatedStorage.Shared.Requirements.InventoryHasRoomFor)
local SkillLevel = require(ReplicatedStorage.Shared.Requirements.SkillLevel)
local RequirementsTypes = require(ReplicatedStorage.Shared.Types.RequirementsTypes)

export type Requirement = RequirementsTypes.Requirement
export type PlayerSnapshot = RequirementsTypes.PlayerSnapshot

local Requirements = {}

--[=[
	@prop SkillLevel (skill: SkillKind, level: number) -> Requirement
	@within Requirements
]=]
Requirements.SkillLevel = SkillLevel.Make

--[=[
	@prop Equipped (slot: EquipmentSlot, itemKind: string) -> Requirement
	@within Requirements
]=]
Requirements.Equipped = Equipped.Make

--[=[
	@prop InventoryHasRoomFor (itemKinds: {string}) -> Requirement
	@within Requirements
]=]
Requirements.InventoryHasRoomFor = InventoryHasRoomFor.Make

--[=[
	Runs `requirements` in order against `snapshot`, returning on the first
	failure. Returns `(true, nil)` when all pass.
	@within Requirements
	@param snapshot PlayerSnapshot
	@param requirements {Requirement}
	@return (boolean, string?)
]=]
function Requirements.Check(snapshot: PlayerSnapshot, requirements: { Requirement }): (boolean, string?)
	for _, requirement in requirements do
		local ok, message = requirement.Check(snapshot)
		if not ok then
			return false, message
		end
	end
	return true, nil
end

return Requirements
