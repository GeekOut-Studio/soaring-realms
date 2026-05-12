local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

return function(props: {
	Ratio: number,
	Aspect: Enum.AspectType?,
	Axis: Enum.DominantAxis?,
})
	return e("UIAspectRatioConstraint", {
		AspectRatio = props.Ratio,
		AspectType = props.Aspect or Enum.AspectType.ScaleWithParentSize,
		DominantAxis = props.Axis or Enum.DominantAxis.Width,
	})
end
