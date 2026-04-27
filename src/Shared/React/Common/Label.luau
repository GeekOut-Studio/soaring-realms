local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)
local FontDefs = require(ReplicatedStorage.Shared.Defs.FontDefs)

local e = React.createElement
local merge = Sift.Dictionary.merge

return function(props: {
	Native: any,
	children: any,
})
	return e(
		"TextLabel",
		merge({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			FontFace = FontDefs.Normal,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 20,
		}, props.Native),
		props.children
	)
end
