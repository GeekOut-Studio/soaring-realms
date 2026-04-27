local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)

local e = React.createElement
local merge = Sift.Dictionary.merge

return function(props: {
	Native: any,
})
	return e(
		"UIGridLayout",
		merge({
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, props.Native)
	)
end
