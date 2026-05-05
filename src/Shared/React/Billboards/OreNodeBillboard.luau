--!strict

--[=[
	@class OreNodeBillboard
	Renderer for an ore-node's world-space progress (and break) bars. Receives an
	`OreNodeClient` and the entry's `Root` part; subscribes to the node's hit
	events for this root and to its `Break` / `State` properties to drive live
	bindings.

	Layout:
	- Always renders the per-player progress bar.
	- Adds a shared break bar above the progress bar only when this entry is the
	  center entry AND the node is in `Normal` state. Per spec, break does not
	  tick in `Bonus`/`Depleted` and the bonus entries never have a break meter.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ProgressBar = require(ReplicatedStorage.Shared.React.Common.ProgressBar)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)

local e = React.createElement

local BAR_HEIGHT_SCALE = 0.4
local BAR_PADDING = UDim.new(0, 2)

local function OreNodeBillboard(props: {
	Node: any,
	Root: BasePart,
	EntryKey: string,
	InitialProgress: number,
}): any
	local progressBinding, setProgress = React.useBinding(props.InitialProgress)
	local breakBinding, setBreak = React.useBinding(0)
	local state, setState = React.useState("Normal")

	React.useEffect(function()
		local connection = props.Node.HitSignal:Connect(function(payload: { Root: BasePart, Progress: number })
			if payload.Root == props.Root then
				setProgress(payload.Progress)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.Node, props.Root })

	React.useEffect(function()
		local connection = props.Node.BreakProperty:Observe(function(value: number)
			setBreak(value)
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.Node })

	React.useEffect(function()
		local connection = props.Node.StateProperty:Observe(function(value: string)
			setState(value)
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.Node })

	local showBreak = props.EntryKey == "Center" and state == "Normal"

	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, {
		Layout = e(VerticalList, {
			Native = {
				Padding = BAR_PADDING,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
			},
		}),
		Progress = e(ProgressBar, {
			FrameNative = {
				LayoutOrder = 2,
				Size = UDim2.fromScale(1, BAR_HEIGHT_SCALE),
			},
			BarNative = {
				BackgroundColor3 = ColorDefs.ActionBarFill,
			},
			LabelNative = {
				Text = "Progress",
				TextScaled = true,
			},
			Alpha = progressBinding,
		}),
		Break = if showBreak
			then e(ProgressBar, {
				FrameNative = {
					LayoutOrder = 1,
					Size = UDim2.fromScale(1, BAR_HEIGHT_SCALE),
				},
				BarNative = {
					BackgroundColor3 = ColorDefs.HealthBarFill,
				},
				LabelNative = {
					Text = "Break",
					TextScaled = true,
				},
				Alpha = breakBinding,
			})
			else nil,
	})
end

return OreNodeBillboard
