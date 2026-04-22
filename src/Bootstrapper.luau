local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local SOURCE_ASSET_ID = 115620699935273

local Bootstrapper = {}

function Bootstrapper.Init()
	local sourceFolder = ServerStorage:FindFirstChild("Source")
	if sourceFolder == nil then
		sourceFolder = InsertService:LoadAsset(SOURCE_ASSET_ID):GetChildren()[1]
		sourceFolder.Parent = ServerStorage
	end

	-- all non-executing code
	sourceFolder.Shared.Parent = ReplicatedStorage
	sourceFolder.Packages.Parent = ReplicatedStorage
	sourceFolder.Assets.Parent = ServerStorage

	-- server-side code
	sourceFolder.Server.Parent = ServerScriptService

	-- client-side code
	local client = sourceFolder.Client
	client.Parent = StarterPlayer.StarterPlayerScripts

	-- account for players that may have already loaded in
	for _, player in Players:GetChildren() do
		local playerScripts = player:FindFirstChild("PlayerScripts")
		if playerScripts == nil then
			continue
		end

		local existingClient = playerScripts:FindFirstChild("Client")
		if existingClient ~= nil then
			continue
		end

		client:Clone().Parent = playerScripts
	end
end

return Bootstrapper
