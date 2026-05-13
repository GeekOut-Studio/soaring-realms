--!strict

-- World-space overhead billboard shared by Denizen and Outworlder. Today it
-- renders just a health bar from two Comm properties; the name is generic so
-- additional combatant-scoped info (stamina, name, level, etc.) can grow here
-- without renaming. Provider components (`DenizenClient`, `OutworlderClient`)
-- handle registration and visibility — this component stays dumb so both
-- providers can reuse it without baking in entity-specific quirks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ProgressBar = require(ReplicatedStorage.Shared.React.Common.ProgressBar)

local e = React.createElement

local function CombatantBillboard(props: {
	HealthProperty: any,
	MaxHealthProperty: any,
}): any
	local initialHealth = props.HealthProperty:Get() :: number
	local initialMax = props.MaxHealthProperty:Get() :: number
	local initialAlpha = if initialMax > 0 then initialHealth / initialMax else 0

	local alphaBinding, setAlpha = React.useBinding(initialAlpha)
	local healthRef = React.useRef(initialHealth)
	local maxRef = React.useRef(initialMax)

	React.useEffect(function()
		local function recompute()
			local max = maxRef.current
			if max <= 0 then
				setAlpha(0)
			else
				setAlpha(healthRef.current / max)
			end
		end

		local healthConn = props.HealthProperty:Observe(function(value: number)
			healthRef.current = value
			recompute()
		end)
		local maxConn = props.MaxHealthProperty:Observe(function(value: number)
			maxRef.current = value
			recompute()
		end)

		return function()
			healthConn:Disconnect()
			maxConn:Disconnect()
		end
	end, { props.HealthProperty, props.MaxHealthProperty } :: { any })

	return e(ProgressBar, {
		FrameNative = {
			Size = UDim2.fromScale(1, 1),
		},
		BarNative = {
			BackgroundColor3 = ColorDefs.HealthBarFill,
		},
		Alpha = alphaBinding,
	})
end

return CombatantBillboard
