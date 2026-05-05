--!strict

--[=[
	@class RequirementsServer
	Server-side wrapper around the shared `Requirements` algorithm. Builds a
	`PlayerSnapshot` from `DataServer` (the authoritative source) synchronously
	and runs the check against it.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)

local RequirementsServer = {}

--[=[
	Returns `(ok: boolean, message: string?)` reflecting the first failure in
	`requirements` against the player's current data.
	@within RequirementsServer
	@server
	@param player Player
	@param requirements {Requirement}
	@return (boolean, string?)
]=]
function RequirementsServer.CheckForPlayer(
	player: Player,
	requirements: { Requirements.Requirement }
): (boolean, string?)
	local data = DataServer.GetData(player)
	if data == nil then
		return false, "Still loading your data; try again in a moment."
	end
	local snapshot: Requirements.PlayerSnapshot = {
		Skills = (data :: any).Skills,
		Inventory = (data :: any).Inventory,
		Equipment = (data :: any).Equipment,
	}
	return Requirements.Check(snapshot, requirements)
end

return RequirementsServer
