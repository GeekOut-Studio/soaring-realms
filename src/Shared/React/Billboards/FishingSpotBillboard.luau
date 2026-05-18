--!strict

--[=[
	@class FishingSpotBillboard
	Renderer for a fishing spot's world-space frenzy bar. Receives a
	`FishingSpotClient` and subscribes to its `State`, `Frenzy`, and
	`FrenzyExpiresAt` properties.

	Three display modes:
	- `"Normal"` — the bar shows the build-up meter (server-replicated `Frenzy`
	  property, 0..1).
	- `"Frenzy"` — the bar starts at full and drains over `FrenzyDuration`
	  seconds. The countdown is driven locally from `FrenzyExpiresAt` (a
	  server-time stamp pushed once on entry) plus the shared
	  `FrenzyDuration` constant — no per-Heartbeat replication.
	- `"Suppressed"` — a sibling spot in the group is currently frenzied, so
	  this spot's bar is hidden entirely.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local FishingShared = require(ReplicatedStorage.Shared.FishingShared)
local ProgressBar = require(ReplicatedStorage.Shared.React.Common.ProgressBar)

local e = React.createElement

local BAR_HEIGHT_SCALE = 0.4

local function FishingSpotBillboard(props: {
	Node: any,
}): any
	local fillBinding, setFill = React.useBinding(0)
	local state, setState = React.useState("Normal")

	React.useEffect(function()
		local connection = props.Node.StateProperty:Observe(function(value: string)
			setState(value)
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.Node })

	React.useEffect(function()
		if state == "Suppressed" then
			return
		end
		if state == "Frenzy" then
			-- Countdown is driven locally from the one-shot `FrenzyExpiresAt`
			-- timestamp; no need to subscribe to per-tick `Frenzy` updates.
			local expiresAt = props.Node.FrenzyExpiresAtProperty:Get() or 0
			local expiresConnection = props.Node.FrenzyExpiresAtProperty:Observe(function(value: number)
				expiresAt = value
			end)
			local heartbeat = RunService.Heartbeat:Connect(function()
				local remaining = expiresAt - Workspace:GetServerTimeNow()
				setFill(math.clamp(remaining / FishingShared.FrenzyDuration, 0, 1))
			end)
			return function()
				heartbeat:Disconnect()
				expiresConnection:Disconnect()
			end
		end

		setFill(props.Node.FrenzyProperty:Get() or 0)
		local connection = props.Node.FrenzyProperty:Observe(function(value: number)
			setFill(math.clamp(value, 0, 1))
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.Node, state })

	if state == "Suppressed" then
		return nil
	end

	local isFrenzy = state == "Frenzy"
	local label = if isFrenzy then "FRENZY!" else "Frenzy"
	local barColor = if isFrenzy then ColorDefs.HealthBarFill else ColorDefs.ActionBarFill

	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, {
		Progress = e(ProgressBar, {
			FrameNative = {
				Size = UDim2.fromScale(1, BAR_HEIGHT_SCALE),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
			},
			BarNative = {
				BackgroundColor3 = barColor,
			},
			LabelNative = {
				Text = label,
				TextScaled = true,
			},
			Alpha = fillBinding,
		}),
	})
end

return FishingSpotBillboard
