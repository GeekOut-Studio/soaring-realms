local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Flipper = require(ReplicatedStorage.Packages.Flipper)
local React = require(ReplicatedStorage.Packages.React)
local TeleportClient = require(ReplicatedStorage.Shared.Clients.TeleportClient)
local UseMotor = require(ReplicatedStorage.Shared.React.Hooks.UseMotor)

local e = React.createElement

local DISPLAY_ORDER = 9999
local CIRCLE_COLOR = Color3.fromRGB(100, 180, 255)

local function TeleportOverlay()
	local isTeleporting, setIsTeleporting = React.useState(false)
	local binding, motor = UseMotor(0)
	local screenGuiRef = React.useRef(nil)

	React.useEffect(function()
		return TeleportClient.ObserveIsTeleporting(function(value)
			setIsTeleporting(value)
		end)
	end, {})

	React.useEffect(function()
		if isTeleporting then
			motor:setGoal(Flipper.Spring.new(1, { frequency = 2, dampingRatio = 1 }))
		else
			motor:setGoal(Flipper.Instant.new(0))
		end
	end, { isTeleporting })

	React.useEffect(function()
		if isTeleporting and screenGuiRef.current ~= nil then
			TeleportService:SetTeleportGui(screenGuiRef.current)
		end
	end, { isTeleporting })

	if not isTeleporting then
		return nil
	end

	return e("ScreenGui", {
		ref = screenGuiRef,
		DisplayOrder = DISPLAY_ORDER,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		Circle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			Size = binding:map(function(value)
				return UDim2.fromScale(value * 2, value * 2)
			end),
			BackgroundColor3 = CIRCLE_COLOR,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.5, 0),
			}),
		}),
	})
end

return TeleportOverlay
