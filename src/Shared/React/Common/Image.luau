local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)

local e = React.createElement
local merge = Sift.Dictionary.merge

return function(props: {
	Native: any,
	children: any,
})
	return e(
		"ImageLabel",
		merge({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, props.Native),
		props.children
	)
end
