local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local manifestSource = sharedFolder:WaitForChild("ClientManifest") :: ModuleScript
local ClientManifest = require(manifestSource)

local function waitForManifest(parent: Instance, manifest: { [string]: any })
	for name, children in manifest do
		local child = parent:WaitForChild(name)
		if type(children) == "table" then
			waitForManifest(child, children)
		end
	end
end

waitForManifest(ReplicatedStorage, ClientManifest)

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
