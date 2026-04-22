local Players = game:GetService("Players")

local playerScripts = Players.LocalPlayer.PlayerScripts

if playerScripts:FindFirstChild("Client") ~= nil then
	script:Destroy()
	return
end

local client = script.Parent:WaitForChild("Client")
client.Parent = playerScripts

for _, desc in client:GetDescendants() do
	if desc:IsA("BaseScript") then
		desc.Enabled = true
	end
end

script:Destroy()
