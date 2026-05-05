--!strict

--[=[
	@class ProgressBar
	A black-background-with-colored-fill bar with an optional label-in-bar (text
	plus stroke). Used in screen-space HUD elements (`ActionProgressBar`) and in
	world-space billboards (`OreNodeBillboard`).

	Each of the three sub-elements takes its own `Native` prop:
	- `FrameNative` — the outer container Frame. Merge target for layout (`Size`,
	  `LayoutOrder`, `Position`) and background color overrides.
	- `BarNative` — the inner fill Frame. Merge target for fill color, border, etc.
	  `Size` is host-controlled (driven by `Alpha`) and silently overridden.
	- `LabelNative` — props for the `Label` text. `nil` to omit the label entirely.

	`Alpha` may be a plain number or a React binding — bindings let callers drive
	the fill width per-Heartbeat without re-rendering the surrounding subtree.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local TextStroke = require(ReplicatedStorage.Shared.React.Common.TextStroke)

local e = React.createElement
local merge = Sift.Dictionary.merge

local function ProgressBar(props: {
	FrameNative: any,
	BarNative: any,
	LabelNative: any?,
	Alpha: number | React.Binding<number>,
}): any
	local alpha = props.Alpha
	local fillSize: any
	if typeof(alpha) == "number" then
		fillSize = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	else
		fillSize = (alpha :: React.Binding<number>):map(function(v: number)
			return UDim2.fromScale(math.clamp(v, 0, 1), 1)
		end)
	end

	return e(
		"Frame",
		merge({
			BorderSizePixel = 0,
			BackgroundColor3 = ColorDefs.Black,
		}, props.FrameNative),
		{
			Fill = e(
				"Frame",
				merge(
					merge({
						BorderSizePixel = 0,
						BackgroundColor3 = Color3.new(1, 1, 1),
					}, props.BarNative or {}),
					{ Size = fillSize }
				)
			),
			LabelHolder = if props.LabelNative ~= nil
				then e(Label, {
					Native = merge({ ZIndex = 2 }, props.LabelNative),
				}, {
					Stroke = e(TextStroke, { Native = {} }),
				})
				else nil,
		}
	)
end

return ProgressBar
