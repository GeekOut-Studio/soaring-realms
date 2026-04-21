local ServerScriptService = game:GetService("ServerScriptService")

local DownloadServer = require(ServerScriptService.Server.Servers.DownloadServer)
local GameServer = require(ServerScriptService.Server.Servers.GameServer)
local TeleportServer = require(ServerScriptService.Server.Servers.TeleportServer)
require(ServerScriptService.Server.Components.IslandTeleporter)

DownloadServer.Init()
GameServer.Init()
TeleportServer.Init()
