-- Returns the shared `workspace.Effects` folder used to parent transient effect instances
-- (attachments for positional sounds, particle emitters, etc.). Creates the folder on first
-- call. Standalone helper so any effect can grab the folder without routing through
-- EffectClient and inviting a require cycle.

local effectsFolder: Folder? = nil

return function(): Folder
	if effectsFolder ~= nil and effectsFolder.Parent ~= nil then
		return effectsFolder
	end

	local existing = workspace:FindFirstChild("Effects")
	if existing ~= nil and existing:IsA("Folder") then
		effectsFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = workspace
	effectsFolder = folder
	return folder
end
