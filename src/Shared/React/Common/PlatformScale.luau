local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

local SCALE_CONSOLE = 1.5
local SCALE_TABLET = 0.75
local SCALE_PHONE = 0.5
local SCALE_DESKTOP = 1.0

local PHONE_MAX_WIDTH = 600
local TABLET_MAX_WIDTH = 1024

local function computeScale(viewportWidth: number): number
	if GuiService:IsTenFootInterface() then
		return SCALE_CONSOLE
	elseif viewportWidth < PHONE_MAX_WIDTH then
		return SCALE_PHONE
	elseif viewportWidth < TABLET_MAX_WIDTH then
		return SCALE_TABLET
	else
		return SCALE_DESKTOP
	end
end

--[=[
	@class PlatformScale
	Renders a `UIScale` sized to the current platform and viewport. Drop it as a
	child of any `ScreenGui` that needs platform-adaptive scaling. No props required.

	Console uses a fixed scale. Touch devices split into phone/tablet at
	`PHONE_THRESHOLD` viewport width. Desktop is fixed. All constants are at the
	top of this file.
]=]
return function()
	local viewport, setViewport = React.useState(workspace.CurrentCamera.ViewportSize)

	React.useEffect(function()
		local conn = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setViewport(workspace.CurrentCamera.ViewportSize)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return e("UIScale", { Scale = computeScale(viewport.X) })
end
