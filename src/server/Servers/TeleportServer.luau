--[=[
	@class TeleportServer
	Handles teleporting groups of players to island places and tracks teleport state via Comm.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Promise = require(ReplicatedStorage.Packages.Promise)
local DataServer = require(ServerScriptService.Server.Servers.DataServer)
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

	-- Release each player's ProfileStore session before teleporting so the destination
	-- server can `StartSessionAsync` immediately. Run in parallel and wait for all to
	-- finish (or fail) before initiating the actual teleport.
	local endPromises = {}
	for _, player in players do
		table.insert(
			endPromises,
			Promise.new(function(resolve)
				DataServer.EndSessionForTeleport(player)
				resolve(nil)
			end)
		)
	end
	Promise.allSettled(endPromises):await()

	local success, err = pcall(TeleportService.TeleportAsync, TeleportService, def.PlaceId, players)
	if not success then
		warn(`TeleportServer: Failed to teleport to {islandKind}: {err}`)
		-- We've already released their sessions, so we can't gracefully recover this
		-- server's view of their data. Kick so they rejoin and reload cleanly from
		-- whatever the last save flushed.
		for _, player in players do
			isTeleporting:SetFor(player, false)
			player:Kick("Teleport failed. Please rejoin.")
		end
	end

	return success
end

return TeleportServer
