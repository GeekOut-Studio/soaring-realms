local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)

local TestClient = {}

function TestClient.Init()
	task.spawn(function()
		local player = Players.LocalPlayer
		local character = player.Character or player.CharacterAdded:Wait()
		local rightHand = character:WaitForChild("RightHand")

		local sword = DownloadClient.DownloadAsync("Base/Weapons/SwordTest")
		assert(sword.PrimaryPart ~= nil, "SwordTest has no PrimaryPart")

		sword:PivotTo(rightHand.CFrame)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = sword.PrimaryPart
		weld.Part1 = rightHand
		weld.Parent = sword.PrimaryPart

		sword.Parent = character
	end)
end

return TestClient
