--[=[
	@class DownloadClient
	Downloads and caches server-side assets to the client via Comm.

	Each asset is fetched once and cloned on subsequent requests. Concurrent requests for
	the same path share a single in-flight fetch.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Promise = require(ReplicatedStorage.Packages.Promise)

local DownloadClient = {}

local download
local acknowledgeSignal
local cacheFolder
local downloadPromises: { [string]: any } = {}

local function waitForLeaf(root: Instance, path: string)
	local parts = string.split(path, "/")
	local current = root
	for _, part in parts do
		current = current:WaitForChild(part)
	end
end

function DownloadClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Download")
	download = clientComm:GetFunction("Download")
	acknowledgeSignal = clientComm:GetSignal("AcknowledgeAsset")

	cacheFolder = Instance.new("Folder")
	cacheFolder.Name = "DownloadCache"
	cacheFolder.Parent = ReplicatedStorage
end

--[=[
	Downloads the asset at `path` and resolves with a clone of it.

	On the first call for a given path, fetches the asset from the server, waits for all
	manifest leaves to replicate, caches it, and acknowledges receipt. Concurrent calls
	for the same path share the in-flight fetch. Subsequent calls after caching resolve
	with a fresh clone without a server round-trip.
	@within DownloadClient
	@param path string -- Slash-delimited asset path (e.g. `"Weapons/CopperSword"`).
	@return Promise<Instance> -- Resolves with a clone of the downloaded asset.
]=]
function DownloadClient.Download(path: string): any
	local existing = downloadPromises[path]
	if existing ~= nil then
		return existing:andThen(function(asset)
			return asset:Clone()
		end)
	end

	local promise = Promise.new(function(resolve, _reject)
		local result = download(path)
		local containerName = result.ContainerName
		local assetName = result.AssetName
		local manifest = result.Manifest

		local playerGui = Players.LocalPlayer.PlayerGui
		local container = playerGui:WaitForChild(containerName)
		local downloaded = container:WaitForChild(assetName)

		for _, leafPath in manifest do
			waitForLeaf(downloaded, leafPath)
		end

		local asset = downloaded:Clone()
		asset.Parent = cacheFolder
		acknowledgeSignal:Fire(containerName)
		resolve(asset)
	end)

	downloadPromises[path] = promise

	promise:catch(function()
		if downloadPromises[path] == promise then
			downloadPromises[path] = nil
		end
	end)

	return promise:andThen(function(asset)
		return asset:Clone()
	end)
end

return DownloadClient
