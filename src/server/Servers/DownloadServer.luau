local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)

local DownloadServer = {}

local function getLeafPaths(instance: Instance): { string }
	local paths = {}

	local function recurse(inst: Instance, prefix: string)
		local children = inst:GetChildren()
		if #children == 0 then
			if prefix ~= "" then
				table.insert(paths, prefix)
			end
			return
		end
		for _, child in children do
			local childPath = if prefix == "" then child.Name else prefix .. "/" .. child.Name
			recurse(child, childPath)
		end
	end

	recurse(instance, "")
	return paths
end

local function resolvePath(path: string): Instance?
	local parts = string.split(path, "/")
	local current: Instance = ServerStorage.Assets
	for _, part in parts do
		local child = current:FindFirstChild(part)
		if child == nil then
			return nil
		end
		current = child
	end
	return current
end

function DownloadServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Download")

	serverComm:CreateSignal("AcknowledgeAsset"):Connect(function(player: Player, containerName: string)
		local container = player.PlayerGui:FindFirstChild(containerName)
		if container ~= nil then
			container:Destroy()
		end
	end)

	serverComm:BindFunction("DownloadAsync", function(player: Player, path: string)
		local asset = resolvePath(path)
		assert(asset ~= nil, "Asset not found: " .. tostring(path))

		local clone = asset:Clone()
		local manifest = getLeafPaths(clone)

		local containerName = HttpService:GenerateGUID(false)
		local container = Instance.new("Folder")
		container.Name = containerName
		clone.Parent = container
		container.Parent = player.PlayerGui

		return {
			ContainerName = containerName,
			AssetName = asset.Name,
			Manifest = manifest,
		}
	end)
end

return DownloadServer
