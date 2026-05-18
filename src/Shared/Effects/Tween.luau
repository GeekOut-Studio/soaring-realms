-- Effect module: tweens properties on `Instance` to the values in `Properties` over
-- `Duration` seconds. Drives the interpolation via our `Timeline` helper and uses
-- `TweenService:GetValue` only for the easing curve, so cancellation and Heartbeat
-- ownership match the rest of our timed-effect code. Caller can pass `EasingStyle`
-- and `EasingDirection` (default Linear / Out).
--
-- Interpolation is per-property by type: numbers via arithmetic, Vector3/Vector2/
-- CFrame/Color3/UDim2 via `:Lerp`, anything else holds the start value and snaps to
-- the target at completion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Timeline = require(ReplicatedStorage.Shared.Timeline)

type Args = {
	Instance: Instance,
	Properties: { [string]: any },
	Duration: number,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
}

local function lerp(a: any, b: any, t: number): any
	local typeName = typeof(a)
	if typeName == "number" then
		return a + (b - a) * t
	elseif
		typeName == "Vector3"
		or typeName == "Vector2"
		or typeName == "CFrame"
		or typeName == "Color3"
		or typeName == "UDim2"
	then
		return a:Lerp(b, t)
	end
	return if t >= 1 then b else a
end

return function(args: Args)
	local instance = args.Instance
	local target = args.Properties
	local style = args.EasingStyle or Enum.EasingStyle.Linear
	local direction = args.EasingDirection or Enum.EasingDirection.Out

	local initial: { [string]: any } = {}
	for prop in target do
		initial[prop] = (instance :: any)[prop]
	end

	Timeline(args.Duration, function(alpha)
		local eased = TweenService:GetValue(alpha, style, direction)
		for prop, finalValue in target do
			(instance :: any)[prop] = lerp(initial[prop], finalValue, eased)
		end
	end)
end
