local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cmdr = require(ReplicatedStorage.Packages.Cmdr)
local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local DownloadServer = require(ServerScriptService.Server.Servers.DownloadServer)
local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local GameServer = require(ServerScriptService.Server.Servers.GameServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local TeleportServer = require(ServerScriptService.Server.Servers.TeleportServer)

DataServer.Init()
DownloadServer.Init()
GameServer.Init()
TeleportServer.Init()
InventoryServer.Init()
EquipmentServer.Init()

for _, component in ServerScriptService.Server.Components:GetChildren() do
	require(component)
end

Cmdr:RegisterDefaultCommands()
Cmdr:RegisterCommandsIn(ReplicatedStorage.Shared.Cmdr.Commands)
Cmdr:RegisterHooksIn(ReplicatedStorage.Shared.Cmdr.Hooks)
Cmdr:RegisterTypesIn(ReplicatedStorage.Shared.Cmdr.Types)
