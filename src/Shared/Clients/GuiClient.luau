local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local App = require(ReplicatedStorage.Shared.React.App)

local GuiClient = {}

function GuiClient.Init()
	local root = ReactRoblox.createRoot(Instance.new("Folder"))
	root:render(ReactRoblox.createPortal(React.createElement(App), Players.LocalPlayer.PlayerGui))
end

return GuiClient
