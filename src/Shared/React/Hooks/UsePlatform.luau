-- React hook returning the estimated platform for the local viewport. Console
-- is detected via `GuiService:IsTenFootInterface()`. Input mode then decides
-- the touch vs. mouse tier: touch-only devices split into Phone/Tablet by the
-- shorter viewport axis (stable across orientation — Roblox phones default to
-- landscape, so width alone misclassifies them as tablets), and anything with
-- a mouse is treated as Desktop regardless of resolution so low-res monitors
-- don't get mis-shrunk. Reactive to viewport and input-mode changes.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

export type Platform = "Console" | "Phone" | "Tablet" | "Desktop"

local PHONE_MAX_SHORT_AXIS = 500

local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function computePlatform(viewport: Vector2, touchOnly: boolean): Platform
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if not touchOnly then
		return "Desktop"
	end
	local shortAxis = math.min(viewport.X, viewport.Y)
	if shortAxis < PHONE_MAX_SHORT_AXIS then
		return "Phone"
	else
		return "Tablet"
	end
end

return function(): Platform
	local viewport, setViewport = React.useState(Workspace.CurrentCamera.ViewportSize)
	local touchOnly, setTouchOnly = React.useState(isTouchOnly())

	React.useEffect(function()
		local trove = Trove.new()

		local cameraTrove
		local function bindCamera()
			trove:Remove(cameraTrove)
			cameraTrove = trove:Extend()
			local camera = Workspace.CurrentCamera
			if camera == nil then
				return
			end
			setViewport(camera.ViewportSize)
			cameraTrove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
				setViewport(camera.ViewportSize)
			end)
		end
		trove:Connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
		bindCamera()

		local function refreshTouchOnly()
			setTouchOnly(isTouchOnly())
		end
		trove:Connect(UserInputService:GetPropertyChangedSignal("TouchEnabled"), refreshTouchOnly)
		trove:Connect(UserInputService:GetPropertyChangedSignal("MouseEnabled"), refreshTouchOnly)
		refreshTouchOnly()

		return trove:WrapClean()
	end, {})

	return computePlatform(viewport, touchOnly)
end
