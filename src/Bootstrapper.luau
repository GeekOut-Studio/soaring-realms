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

	-- server-side code; capture helper before the move
	local earlyHelper = sourceFolder.Server.BootstrapperEarlyPlayerHelper
	sourceFolder.Server.Parent = ServerScriptService

	-- client-side code
	local client = sourceFolder.Client
	client.Parent = StarterPlayer.StarterPlayerScripts

	-- account for players that may have already loaded in
	for _, player in Players:GetChildren() do
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui == nil then
			continue
		end

		if playerGui:FindFirstChild("Client") ~= nil then
			continue
		end

		local clientClone = client:Clone()
		for _, desc in clientClone:GetDescendants() do
			if desc:IsA("BaseScript") then
				desc.Enabled = false
			end
		end
		clientClone.Parent = playerGui

		earlyHelper:Clone().Parent = playerGui
	end
end

return Bootstrapper
