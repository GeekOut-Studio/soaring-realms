--[=[
	@class DownloadClient
	Downloads and caches server-side assets to the client via Comm.
	Each asset is fetched once and cloned on subsequent requests.
]=]

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

--[=[
	Downloads the asset at `path` and returns a clone of it.

	On the first call for a given path, fetches the asset from the server, waits for all
	manifest leaves to replicate, caches it, and acknowledges receipt. Subsequent calls
	return a clone directly from cache without a server round-trip.
	@within DownloadClient
	@param path string -- Slash-delimited asset path (e.g. `"Weapons/CopperSword"`).
	@return Instance -- A clone of the downloaded asset.
]=]
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
