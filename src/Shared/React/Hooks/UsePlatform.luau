-- React hook returning the estimated platform for the local viewport. Console
-- is detected via `GuiService:IsTenFootInterface()`; phone/tablet/desktop are
-- distinguished by the shorter viewport axis (stable across orientation, and
-- the right signal for "physical smallness" — Roblox phones default to
-- landscape, so width alone misclassifies them as tablets). Reactive to
-- viewport changes.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)

export type Platform = "Console" | "Phone" | "Tablet" | "Desktop"

local PHONE_MAX_SHORT_AXIS = 500
local TABLET_MAX_SHORT_AXIS = 900

local function computePlatform(viewport: Vector2): Platform
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	local shortAxis = math.min(viewport.X, viewport.Y)
	if shortAxis < PHONE_MAX_SHORT_AXIS then
		return "Phone"
	elseif shortAxis < TABLET_MAX_SHORT_AXIS then
		return "Tablet"
	else
		return "Desktop"
	end
end

return function(): Platform
	local viewport, setViewport = React.useState(Workspace.CurrentCamera.ViewportSize)

	React.useEffect(function()
		local conn = Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setViewport(Workspace.CurrentCamera.ViewportSize)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return computePlatform(viewport)
end
