local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Observers = require(ReplicatedStorage.Packages.Observers)

local OUTWORLDER_TAG = "Outworlder"

local GameServer = {}

function GameServer.Init()
	Observers.observeCharacter(function(_player, character)
		CollectionService:AddTag(character, OUTWORLDER_TAG)
		return function()
			CollectionService:RemoveTag(character, OUTWORLDER_TAG)
		end
	end)

	Observers.observePlayer(function(player)
		-- initialize player

		return function()
			-- clean up player
		end
	end)
end

return GameServer
