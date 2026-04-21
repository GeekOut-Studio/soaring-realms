local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local GuiClient = require(ReplicatedStorage.Shared.Clients.GuiClient)
local TeleportClient = require(ReplicatedStorage.Shared.Clients.TeleportClient)
local TestClient = require(ReplicatedStorage.Shared.Clients.TestClient)

DownloadClient.Init()
GuiClient.Init()
TeleportClient.Init()
TestClient.Init()

for _, component in ReplicatedStorage.Shared.Components:GetChildren() do
	require(component)
end
