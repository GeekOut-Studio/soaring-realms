--!strict

--[=[
	@class TreeNodeBillboard
	Renderer for a tree-node's world-space progress (and cut) bars. Receives a
	`TreeNodeClient` and the entry's `Root` part; subscribes to the node's hit
	events for this root and to its `Cut` / `State` properties to drive live
	bindings.

	Layout:
	- Always renders the per-player progress bar.
	- Adds a shared cut bar above the progress bar only when this entry is the
	  stump entry AND the node is in `Normal` state. Per spec, cut does not tick
	  in `Bonus`/`Depleted` and the trunk entry never has a cut meter.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ProgressBar = require(ReplicatedStorage.Shared.React.Common.ProgressBar)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)

local e = React.createElement

local BAR_HEIGHT_SCALE = 0.4
local BAR_PADDING = UDim.new(0, 2)

local function TreeNodeBillboard(props: {
	Node: any,
	Root: BasePart,
	EntryKey: string,
	InitialProgress: number,
}): any
	local progressBinding, setProgress = React.useBinding(props.InitialProgress)
	local cutBinding, setCut = React.useBinding(0)
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
		local connection = props.Node.CutProperty:Observe(function(value: number)
			setCut(value)
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

	local showCut = props.EntryKey == "Stump" and state == "Normal"

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
		Cut = if showCut
			then e(ProgressBar, {
				FrameNative = {
					LayoutOrder = 1,
					Size = UDim2.fromScale(1, BAR_HEIGHT_SCALE),
				},
				BarNative = {
					BackgroundColor3 = ColorDefs.HealthBarFill,
				},
				LabelNative = {
					Text = "Cut",
					TextScaled = true,
				},
				Alpha = cutBinding,
			})
			else nil,
	})
end

return TreeNodeBillboard
