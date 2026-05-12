local ServerScriptService = game:GetService("ServerScriptService")

local AbilityServer = require(ServerScriptService.Server.Servers.AbilityServer)
local Cmdr = require(ServerScriptService.ServerPackages.Cmdr)
local CombatServer = require(ServerScriptService.Server.Servers.CombatServer)
local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local DownloadServer = require(ServerScriptService.Server.Servers.DownloadServer)
local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local GameServer = require(ServerScriptService.Server.Servers.GameServer)
local HotbarServer = require(ServerScriptService.Server.Servers.HotbarServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local SkillServer = require(ServerScriptService.Server.Servers.SkillServer)
local TeleportServer = require(ServerScriptService.Server.Servers.TeleportServer)

DataServer.Init()
DownloadServer.Init()
GameServer.Init()
TeleportServer.Init()
InventoryServer.Init()
EquipmentServer.Init()
SkillServer.Init()
CombatServer.Init()
AbilityServer.Init()
HotbarServer.Init()

for _, component in ServerScriptService.Server.Components:GetChildren() do
	require(component)
end

Cmdr:RegisterDefaultCommands()
Cmdr:RegisterCommandsIn(ServerScriptService.Server.Cmdr.Commands)
Cmdr:RegisterHooksIn(ServerScriptService.Server.Cmdr.Hooks)
Cmdr:RegisterTypesIn(ServerScriptService.Server.Cmdr.Types)
