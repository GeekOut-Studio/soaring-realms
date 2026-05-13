local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)

local e = React.createElement
local merge = Sift.Dictionary.merge

return function(props: {
	Native: any,
	children: any,
})
	return e(
		"Frame",
		merge({
			BackgroundColor3 = ColorDefs.PanelBackground,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, props.Native),
		props.children
	)
end
