local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)

local function computeInitial(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--[=[
	@within UseIsMobile
	@function UseIsMobile

	React hook returning whether the local device should display
	mobile-style touch controls.

	Initial value uses the static device-capability heuristic
	(`TouchEnabled and not KeyboardEnabled`). The hook then subscribes
	to `UserInputService.LastInputTypeChanged` and flips the value when
	the player switches input modality — touch → mobile, anything else
	→ desktop.

	@return boolean
]=]
return function(): boolean
	local isMobile, setIsMobile = React.useState(computeInitial)

	React.useEffect(function()
		local conn = UserInputService.LastInputTypeChanged:Connect(function(lastInputType: EnumItem)
			setIsMobile(lastInputType == Enum.UserInputType.Touch)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return isMobile
end
