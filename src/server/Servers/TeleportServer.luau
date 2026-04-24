--[=[
	@class TeleportServer
	Handles teleporting groups of players to island places and tracks teleport state via Comm.
]=]

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

--[=[
	Teleports a group of players to the place for `islandKind`.

	Sets each player's `IsTeleporting` Comm property to `true` before the call.
	On failure, resets all players back to `false` and warns.
	@within TeleportServer
	@param players {Player} -- The players to teleport.
	@param islandKind IslandKind -- The destination island.
	@return boolean -- Whether the TeleportService call succeeded.
]=]
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
