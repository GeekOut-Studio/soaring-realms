local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local App = require(ReplicatedStorage.Shared.React.App)

local GuiClient = {}

function GuiClient.Init()
	local tree = ReactRoblox.createRoot(Players.LocalPlayer.PlayerGui)
	tree:render(React.createElement(App))
end

return GuiClient
