local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local FontDefs = require(ReplicatedStorage.Shared.Defs.FontDefs)

local e = React.createElement
local merge = Sift.Dictionary.merge

return function(props: {
	Native: any,
	children: any,
})
	return e(
		"TextButton",
		merge({
			BackgroundColor3 = ColorDefs.ButtonIdle,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			FontFace = FontDefs.Normal,
			TextColor3 = ColorDefs.TextPrimary,
			TextSize = 20,
			TextWrapped = true,
		}, props.Native),
		props.children
	)
end
