local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

return function(props: {
	Padding: UDim,
})
	return e("UIPadding", {
		PaddingTop = props.Padding,
		PaddingBottom = props.Padding,
		PaddingLeft = props.Padding,
		PaddingRight = props.Padding,
	})
end
