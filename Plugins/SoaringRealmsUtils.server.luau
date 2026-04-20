local toolbar = plugin:CreateToolbar("Soaring Realms")
local packButton = toolbar:CreateButton("Pack", "Pack source into a ServerStorage/Source folder and prompt to save", "")

packButton.Click:Connect(function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Selection = game:GetService("Selection")
	local ServerScriptService = game:GetService("ServerScriptService")
	local ServerStorage = game:GetService("ServerStorage")
	local StarterPlayer = game:GetService("StarterPlayer")

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
