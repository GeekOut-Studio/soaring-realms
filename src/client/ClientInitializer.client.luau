local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- wait for all necessary files
local isDevelopmentPlace = ReplicatedStorage:FindFirstChild("IsDevelopmentPlace")
isDevelopmentPlace = isDevelopmentPlace ~= nil and isDevelopmentPlace.Value

if not (isDevelopmentPlace or RunService:IsStudio()) then
	local ClientManifest = require(script.Parent:WaitForChild("ClientManifest"))

	local function waitForManifest(parent: Instance, manifest: { [string]: any })
		for name, children in manifest do
			local child = parent:WaitForChild(name)
			if type(children) == "table" then
				waitForManifest(child, children)
			end
		end
	end

	waitForManifest(ReplicatedStorage, ClientManifest)
end

-- initialize the client
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
