local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)

local e = React.createElement
local merge = Sift.Dictionary.merge

local function FlexFill(props: {
	Native: any,
	children: any,
})
	return e(
		"UIFlexItem",
		merge({
			FlexMode = Enum.UIFlexMode.Fill,
		}, props.Native),
		props.children
	)
end

return FlexFill
