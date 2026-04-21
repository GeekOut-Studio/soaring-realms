local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)

local DownloadClient = {}

local downloadAsync
local acknowledgeSignal
local cacheFolder
local cache = {}

local function waitForLeaf(root: Instance, path: string)
	local parts = string.split(path, "/")
	local current = root
	for _, part in parts do
		current = current:WaitForChild(part)
	end
end

function DownloadClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Download")
	downloadAsync = clientComm:GetFunction("DownloadAsync")
	acknowledgeSignal = clientComm:GetSignal("AcknowledgeAsset")

	cacheFolder = Instance.new("Folder")
	cacheFolder.Name = "DownloadCache"
	cacheFolder.Parent = ReplicatedStorage
end

function DownloadClient.DownloadAsync(path: string): Instance
	if cache[path] then
		return cache[path]:Clone()
	end

	local result = downloadAsync(path)
	local containerName = result.ContainerName
	local assetName = result.AssetName
	local manifest = result.Manifest

	local playerGui = Players.LocalPlayer.PlayerGui
	local container = playerGui:WaitForChild(containerName)
	local asset = container:WaitForChild(assetName)

	for _, leafPath in manifest do
		waitForLeaf(asset, leafPath)
	end

	asset.Parent = cacheFolder
	cache[path] = asset
	acknowledgeSignal:Fire(containerName)

	return asset:Clone()
end

return DownloadClient
