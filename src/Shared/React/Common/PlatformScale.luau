local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local UsePlatform = require(ReplicatedStorage.Shared.React.Hooks.UsePlatform)

type Platform = UsePlatform.Platform

local e = React.createElement

local SCALE_BY_PLATFORM: { [Platform]: number } = {
	Console = 1.5,
	Tablet = 0.75,
	Phone = 0.5,
	Desktop = 1.0,
}

--[=[
	@class PlatformScale
	Renders a `UIScale` sized to the current platform and viewport. Drop it as a
	child of any `ScreenGui` that needs platform-adaptive scaling. No props required.

	Platform detection lives in `UsePlatform`; this component just maps each
	platform to a scale factor.
]=]
return function()
	local platform = UsePlatform()
	return e("UIScale", { Scale = SCALE_BY_PLATFORM[platform] })
end
