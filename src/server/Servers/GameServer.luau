local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Observers = require(ReplicatedStorage.Packages.Observers)

local GameServer = {}

function GameServer.Init()
	Observers.observePlayer(function(player)
		-- initialize player

		return function()
			-- clean up player
		end
	end)
end

return GameServer
