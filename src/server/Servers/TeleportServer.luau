local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local IslandDefs = require(ReplicatedStorage.Shared.Defs.IslandDefs)
type IslandKind = IslandDefs.IslandKind

local TeleportServer = {}

local isTeleporting

function TeleportServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Teleport")
	isTeleporting = serverComm:CreateProperty("IsTeleporting", false)
end

function TeleportServer.TeleportToIslandAsync(players: { Player }, islandKind: IslandKind)
	local def = IslandDefs[islandKind]
	assert(def ~= nil, "Unknown island: " .. tostring(islandKind))

	for _, player in players do
		isTeleporting:SetFor(player, true)
	end

	local success, err = pcall(TeleportService.TeleportAsync, TeleportService, def.PlaceId, players)
	if not success then
		warn(`TeleportServer: Failed to teleport to {islandKind}: {err}`)
		for _, player in players do
			isTeleporting:SetFor(player, false)
		end
	end

	return success
end

return TeleportServer
