--!strict

--[=[
	@class ActionProgressBar
	Self-contained HUD component that renders a label-over-bar visualization of the
	local player's current action progress.

	Subscribes to the local player's `OutworlderClient` `ActionProgressChanged`
	signal directly. Hosts pass in only layout-related props (e.g. `LayoutOrder`)
	via `Native`; the component manages its own visibility (renders nothing when
	no progress is available) and its own animation state.

	The replicated `ActionProgress` payload may set either `CompletionTimestamp`
	(server-time of cycle completion) or `Alpha` (direct 0..1). When the server
	pushes a new `CompletionTimestamp` mid-cycle, the bar resets to 0 and refills
	toward the new target.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Observers = require(ReplicatedStorage.Packages.Observers)
local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)
local ProgressBar = require(ReplicatedStorage.Shared.React.Common.ProgressBar)

type ActionProgress = ActionTypes.ActionProgress

local e = React.createElement
local merge = Sift.Dictionary.merge

local BAR_HEIGHT = 22

local function ActionProgressBar(props: {
	Native: any,
}): any
	local progress, setProgress = React.useState(nil :: ActionProgress?)
	local fillBinding, setFill = React.useBinding(0)

	React.useEffect(function()
		return Observers.observeCharacter(function(player: Player, character: Model)
			if player ~= Players.LocalPlayer then
				return
			end
			local trove = Trove.new()
			trove:AddPromise(OutworlderClient:WaitForInstance(character):andThen(function(componentInstance)
				setProgress(componentInstance.ActionProgress)
				trove:Add(componentInstance.ActionProgressChanged:Connect(setProgress))
			end))
			return trove:WrapClean()
		end)
	end, {})

	React.useEffect(function()
		if progress == nil then
			setFill(0)
			return
		end
		if progress.Alpha ~= nil then
			setFill(math.clamp(progress.Alpha, 0, 1))
			return
		end
		local completion = progress.CompletionTimestamp
		if completion == nil then
			setFill(0)
			return
		end

		local segmentStart = Workspace:GetServerTimeNow()
		local connection = RunService.Heartbeat:Connect(function()
			local now = Workspace:GetServerTimeNow()
			local total = completion - segmentStart
			local alpha = if total <= 0 then 1 else (now - segmentStart) / total
			setFill(math.clamp(alpha, 0, 1))
		end)
		return function()
			connection:Disconnect()
		end
	end, { progress })

	if progress == nil then
		return nil
	end

	return e(ProgressBar, {
		FrameNative = merge({
			Size = UDim2.fromOffset(0, BAR_HEIGHT),
		}, props.Native),
		BarNative = {
			BackgroundColor3 = ColorDefs.ActionBarFill,
		},
		LabelNative = {
			Text = progress.Name,
		},
		Alpha = fillBinding,
	})
end

return ActionProgressBar
