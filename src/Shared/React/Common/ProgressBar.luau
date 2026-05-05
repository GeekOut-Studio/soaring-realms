--!strict

--[=[
	@class ProgressBar
	A black-background-with-colored-fill bar with an optional label-in-bar (text +
	stroke). Used both in screen-space HUD elements (`ActionProgressBar`) and in
	world-space billboards (`OreNodeBillboard`).

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
	Native: any,
	FillColor: Color3,
	Alpha: number | React.Binding<number>,
	Label: string?,
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
		}, props.Native),
		{
			Fill = e("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = props.FillColor,
				Size = fillSize,
			}),
			LabelHolder = if props.Label ~= nil
				then e(Label, {
					Native = {
						Text = props.Label,
						ZIndex = 2,
					},
				}, {
					Stroke = e(TextStroke, { Native = {} }),
				})
				else nil,
		}
	)
end

return ProgressBar
