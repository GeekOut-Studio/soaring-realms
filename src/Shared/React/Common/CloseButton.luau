local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Aspect = require(ReplicatedStorage.Shared.React.Common.Aspect)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local FontDefs = require(ReplicatedStorage.Shared.Defs.FontDefs)
local TextButton = require(ReplicatedStorage.Shared.React.Common.TextButton)

local e = React.createElement

return function(props: {
	LayoutOrder: number?,
	OnActivated: () -> (),
})
	return e(TextButton, {
		Native = {
			LayoutOrder = props.LayoutOrder,
			-- Intrinsic square fallback for headers without a sibling that drives
			-- row height. Layouts with `ItemLineAlignment.Stretch` (e.g. LootMenu)
			-- still override this and pull the button to the row's height.
			Size = UDim2.fromOffset(28, 28),
			Text = "X",
			TextSize = 20,
			FontFace = FontDefs.Bold,
			[React.Event.Activated] = props.OnActivated,
		},
	}, {
		Stroke = e("UIStroke", {
			Color = ColorDefs.PanelBorder,
			Thickness = 1,
		}),
		Aspect = e(Aspect, {
			Ratio = 1,
		}),
	})
end
