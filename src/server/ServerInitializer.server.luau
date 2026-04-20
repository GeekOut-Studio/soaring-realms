local ServerScriptService = game:GetService("ServerScriptService")

local DownloadServer = require(ServerScriptService.Server.Servers.DownloadServer)
local GameServer = require(ServerScriptService.Server.Servers.GameServer)

DownloadServer.Init()
GameServer.Init()
