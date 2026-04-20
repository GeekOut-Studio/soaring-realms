local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local GuiClient = require(ReplicatedStorage.Shared.Clients.GuiClient)
local TestClient = require(ReplicatedStorage.Shared.Clients.TestClient)

DownloadClient.Init()
GuiClient.Init()
TestClient.Init()
