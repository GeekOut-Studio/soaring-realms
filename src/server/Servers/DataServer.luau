--!strict

--[=[
	@class DataServer
	In-memory player data store. A persistent DataStore implementation will replace this.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)

local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type PlayerData = {
	Inventory: InventoryTypes.Inventory,
	Skills: {},
}

local PLAYER_DATA_TEMPLATE: PlayerData = {
	Inventory = {},
	Skills = {},
}

local DataServer = {}

local dataByPlayer: { [Player]: PlayerData } = {}

function DataServer.Init() end

--[=[
	Returns the player's data, initializing it from the template if this is their first access.
	@within DataServer
	@param player Player
	@return Promise<PlayerData>
]=]
function DataServer.GetData(player: Player)
	if dataByPlayer[player] == nil then
		dataByPlayer[player] = table.freeze(Sift.Dictionary.copyDeep(PLAYER_DATA_TEMPLATE))
	end

	return Promise.resolve(dataByPlayer[player])
end

--[=[
	Applies `updater` to the player's current data and stores the result.
	The returned data is frozen; treat it as immutable.
	@within DataServer
	@param player Player
	@param updater (PlayerData) -> PlayerData -- Pure function that returns the new data.
	@return Promise<PlayerData> -- Resolves with the updated, frozen data.
]=]
function DataServer.UpdateData(player: Player, updater: (PlayerData) -> PlayerData)
	return DataServer.GetData(player):andThen(function(playerData)
		local newData = table.freeze(updater(playerData))
		dataByPlayer[player] = newData
		return newData
	end)
end

return DataServer
