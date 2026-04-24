local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)

type PlayerData = {
	Inventory: {},
	Skills: {},
}

local PLAYER_DATA_TEMPLATE: PlayerData = {
	Inventory = {},
	Skills = {},
}

local DataServer = {}

local dataByPlayer: { [Player]: PlayerData } = {}

function DataServer.Init() end

function DataServer.GetData(player: Player)
	if dataByPlayer[player] == nil then
		dataByPlayer[player] = table.freeze(Sift.Dictionary.copyDeep(PLAYER_DATA_TEMPLATE))
	end

	return Promise.resolve(dataByPlayer[player])
end

function DataServer.UpdateData(player: Player, updater: (PlayerData) -> PlayerData)
	return DataServer.GetData(player):andThen(function(playerData)
		local newData = table.freeze(updater(playerData))
		dataByPlayer[player] = newData
		return newData
	end)
end

return DataServer
