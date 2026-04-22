local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local toolbar = plugin:CreateToolbar("Soaring Realms")
local packButton = toolbar:CreateButton("Pack", "Pack source into a ServerStorage/Source folder and prompt to save", "")

local function isValidIdentifier(name: string): boolean
	return name:match("^[%a_][%w_]*$") ~= nil
end

local function serializeManifestEntry(instance: Instance, depth: number): string
	local children = instance:GetChildren()
	if #children == 0 then
		return "true"
	end
	local indent = string.rep("\t", depth)
	local lines = { "{" }
	for _, child in children do
		local key = if isValidIdentifier(child.Name)
			then child.Name
			else '["' .. child.Name:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"]'
		table.insert(lines, indent .. "\t" .. key .. " = " .. serializeManifestEntry(child, depth + 1) .. ",")
	end
	table.insert(lines, indent .. "}")
	return table.concat(lines, "\n")
end

local function generateClientManifest(parent: Folder, shared: Folder, packages: Folder)
	local source = "return {\n"
		.. "\tShared = "
		.. serializeManifestEntry(shared, 1)
		.. ",\n"
		.. "\tPackages = "
		.. serializeManifestEntry(packages, 1)
		.. ",\n}\n"

	local manifest = Instance.new("ModuleScript")
	manifest.Name = "ClientManifest"
	manifest.Source = source
	manifest.Parent = parent
end

packButton.Click:Connect(function()
	local existing = ServerStorage:FindFirstChild("Source")
	if existing then
		warn("[SoaringRealms Pack] A 'Source' folder already exists in ServerStorage. Remove it first.")
		return
	end

	local sourceFolder = Instance.new("Folder")
	sourceFolder.Name = "Source"

	local function packChild(parent: Instance, name: string)
		local child = parent:FindFirstChild(name)
		if child then
			child:Clone().Parent = sourceFolder
		else
			warn("[SoaringRealms Pack] Could not find '" .. name .. "' under " .. parent:GetFullName())
		end
	end

	packChild(ServerScriptService, "Server")
	packChild(ReplicatedStorage, "Shared")
	packChild(ReplicatedStorage, "Packages")
	packChild(ServerStorage, "Assets")
	packChild(StarterPlayer.StarterPlayerScripts, "Client")

	generateClientManifest(sourceFolder.Shared, sourceFolder.Shared, sourceFolder.Packages)

	sourceFolder.Parent = ServerStorage

	local AssetService = game:GetService("AssetService")
	local ok, assetId, _version = pcall(function()
		return AssetService:CreateAssetAsync(sourceFolder, Enum.AssetType.Model)
	end)

	if ok then
		print("=======================================================")
		print(">> Source packed and uploaded to Roblox!               ")
		print(">> Asset ID: " .. tostring(assetId))
		print("=======================================================")
	else
		-- CreateAssetAsync has known issues; fall back to manual workflow
		warn("[SoaringRealms Pack] CreateAssetAsync failed: " .. tostring(assetId))
		Selection:Set({ sourceFolder })
		print("=======================================================")
		print(">> Source folder created and selected in Explorer.     ")
		print(">> Right-click 'Source' in the Explorer and choose     ")
		print(">>   'Save to Roblox...' to upload it as a model asset.")
		print("=======================================================")
	end

	print("!! REMINDER: DELETE the 'Source' folder from          !!")
	print("!! ServerStorage once the upload is complete!         !!")
	print("=======================================================")
end)
