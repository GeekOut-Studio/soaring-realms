local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Hud = require(ReplicatedStorage.Shared.React.Hud.Hud)
local TeleportOverlay = require(ReplicatedStorage.Shared.React.TeleportOverlay)

local e = React.createElement

local App = function()
	return React.createElement(React.Fragment, nil, {
		GameGui = e("ScreenGui", {
			DisplayOrder = 1,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
		}, {
			Hud = e(Hud),
		}),
		TeleportOverlay = e(TeleportOverlay),
	})
end

return App
