local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local App = function()
	return React.createElement(React.Fragment, nil, {
		GameGui = React.createElement("ScreenGui", {
			DisplayOrder = 1,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ResetOnSpawn = false,
		}, {
			TestLabel = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.XY,
				Text = "Hello, world!",
				Position = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(1, 1),
			}),
		}),
	})
end

return App
