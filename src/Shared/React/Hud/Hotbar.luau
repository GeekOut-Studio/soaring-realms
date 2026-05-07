local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Observers = require(ReplicatedStorage.Packages.Observers)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ActionProgressBar = require(ReplicatedStorage.Shared.React.Hud.ActionProgressBar)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local HealthTypes = require(ReplicatedStorage.Shared.Types.HealthTypes)
local HorizontalList = require(ReplicatedStorage.Shared.React.Common.HorizontalList)
local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)
local TextButton = require(ReplicatedStorage.Shared.React.Common.TextButton)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)

local e = React.createElement

local PADDING = UDim.new(0, 4)
local BAR_HEIGHT = 10
local BUTTON_SIZE = 56

local function Hotbar()
	local stamina, setStamina = React.useState(MovementTypes.MaxStamina)
	local maxStamina, setMaxStamina = React.useState(MovementTypes.MaxStamina)
	local health, setHealth = React.useState(HealthTypes.DefaultMaxHealth)
	local maxHealth, setMaxHealth = React.useState(HealthTypes.DefaultMaxHealth)

	React.useEffect(function()
		return Observers.observeCharacter(function(player: Player, character: Model)
			if player ~= Players.LocalPlayer then
				return
			end
			local trove = Trove.new()
			trove:AddPromise(OutworlderClient:WaitForInstance(character):andThen(function(componentInstance)
				setStamina(componentInstance.Stamina)
				setMaxStamina(componentInstance.MaxStamina)
				trove:Add(componentInstance.StaminaChanged:Connect(setStamina))
				trove:Add(componentInstance.MaxStaminaChanged:Connect(setMaxStamina))
				setHealth(componentInstance.Health)
				setMaxHealth(componentInstance.MaxHealth)
				trove:Add(componentInstance.HealthChanged:Connect(setHealth))
				trove:Add(componentInstance.MaxHealthChanged:Connect(setMaxHealth))
			end))
			return trove:WrapClean()
		end)
	end, {})

	local staminaFraction = math.clamp(stamina / maxStamina, 0, 1)
	local healthFraction = math.clamp(health / maxHealth, 0, 1)

	local hotbarButtons = {}
	for i = 1, 5 do
		hotbarButtons["Button" .. i] = e(TextButton, {
			Native = {
				LayoutOrder = i,
				Text = tostring(i),
				Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			},
		})
	end

	return e(Container, {
		Native = {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
		},
	}, {
		Layout = e(VerticalList, {
			Native = {
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = PADDING,
			},
		}),
		ButtonsRow = e(Container, {
			Native = {
				LayoutOrder = -1,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
			},
		}, {
			Layout = e(HorizontalList, {
				Native = {
					Padding = PADDING,
				},
			}),
			Buttons = e(React.Fragment, nil, hotbarButtons),
		}),
		StaminaBar = e("Frame", {
			LayoutOrder = -2,
			BorderSizePixel = 0,
			BackgroundColor3 = ColorDefs.Black,
			Size = UDim2.fromOffset(0, BAR_HEIGHT),
		}, {
			Bar = e("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = ColorDefs.StaminaBarFill,
				Size = UDim2.fromScale(staminaFraction, 1),
			}),
		}),
		HealthBar = e("Frame", {
			LayoutOrder = -3,
			BorderSizePixel = 0,
			BackgroundColor3 = ColorDefs.Black,
			Size = UDim2.fromOffset(0, BAR_HEIGHT),
		}, {
			Bar = e("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = ColorDefs.HealthBarFill,
				Size = UDim2.fromScale(healthFraction, 1),
			}),
		}),
		ActionProgress = e(ActionProgressBar, {
			Native = {
				LayoutOrder = -4,
			},
		}),
	})
end

return Hotbar
