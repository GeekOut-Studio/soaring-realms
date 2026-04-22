local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
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
			TestLabel = e("TextLabel", {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.XY,
				Text = "Hello, world!",
				Position = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(1, 1),
			}),
		}),
		TeleportOverlay = e(TeleportOverlay),
	})
end

return App
