local ServerScriptService = game:GetService("ServerScriptService")

local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local DownloadServer = require(ServerScriptService.Server.Servers.DownloadServer)
local GameServer = require(ServerScriptService.Server.Servers.GameServer)
local TeleportServer = require(ServerScriptService.Server.Servers.TeleportServer)

DataServer.Init()
DownloadServer.Init()
GameServer.Init()
TeleportServer.Init()

for _, component in ServerScriptService.Server.Components:GetChildren() do
	require(component)
end
