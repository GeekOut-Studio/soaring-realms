local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)

local e = React.createElement

local SLOT_SIZE = 56

local function DragPreview()
	local dragContext = React.useContext(DragContext.Context)
	local position, setPosition = React.useState(UDim2.fromOffset(0, 0))

	React.useEffect(function()
		if dragContext.DragState == nil then
			return
		end

		local mousePos = UserInputService:GetMouseLocation()
		setPosition(UDim2.fromOffset(mousePos.X, mousePos.Y))

		local connection = UserInputService.InputChanged:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				mousePos = UserInputService:GetMouseLocation()
				setPosition(UDim2.fromOffset(mousePos.X, mousePos.Y))
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, { dragContext.DragState } :: { any })

	if dragContext.DragState == nil then
		return nil
	end

	local item = dragContext.DragState.Item
	local def = ItemDefs[item.Kind]
	local name = if def ~= nil then def.Name else item.Kind
	local text = if item.Count ~= nil then name .. "\n×" .. item.Count else name

	return e("ScreenGui", {
		DisplayOrder = 100,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Preview = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			BackgroundColor3 = ColorDefs.SlotBackground,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
		}, {
			ItemLabel = e(Label, {
				Native = {
					TextColor3 = ColorDefs.TextPrimary,
					TextSize = 13,
					TextWrapped = true,
					Text = text,
				},
			}),
			Stroke = e("UIStroke", {
				Color = ColorDefs.SlotBorder,
				Thickness = 2,
			}),
		}),
	})
end

return DragPreview
