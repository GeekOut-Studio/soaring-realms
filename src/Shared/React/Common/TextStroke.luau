local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)

local e = React.createElement
local merge = Sift.Dictionary.merge

local function TextStroke(props: {
	Native: any,
	children: any,
})
	return e(
		"UIStroke",
		merge({
			Thickness = 2,
			Color = Color3.new(0, 0, 0),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, props.Native),
		props.children
	)
end

return TextStroke
