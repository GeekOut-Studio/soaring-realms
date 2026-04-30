local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local GridLayout = require(ReplicatedStorage.Shared.React.Common.GridLayout)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ContextMenuActions = require(ReplicatedStorage.Shared.React.ContextMenuActions)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local DragOrTap = require(ReplicatedStorage.Shared.React.DragOrTap)
local EquipmentClient = require(ReplicatedStorage.Shared.Clients.EquipmentClient)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryClient = require(ReplicatedStorage.Shared.Clients.InventoryClient)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Item = InventoryTypes.Item
type DragItem = DragContext.DragItem

local e = React.createElement

local DRAG_THRESHOLD = 10

type SlotProps = {
	SlotKey: string,
	Item: Item?,
	LayoutOrder: number,
}

local function InventorySlot(props: SlotProps)
	local dragContext = React.useContext(DragContext.Context)
	local contextMenuContext = React.useContext(ContextMenuContext.Context)
	local slotRef = React.useRef(nil :: GuiObject?)
	local isSource = dragContext.DragState ~= nil and dragContext.DragState.SourceSlot == props.SlotKey

	React.useEffect(function()
		local instance = slotRef.current
		if instance == nil then
			return
		end

		dragContext.RegisterDropTarget(props.SlotKey, instance, function(dragItem: DragItem)
			if dragItem.SourceContainer ~= "Inventory" then
				return
			end
			if dragItem.SourceSlot ~= props.SlotKey then
				InventoryClient.MoveItem(dragItem.SourceSlot, props.SlotKey)
			end
		end)

		return function()
			dragContext.UnregisterDropTarget(props.SlotKey, instance)
		end
	end, {})

	local item = props.Item
	local text = ""
	if item ~= nil then
		local def = ItemDefs[item.Kind]
		local name = if def ~= nil then def.Name else item.Kind
		text = if item.Count ~= nil then name .. "\n×" .. item.Count else name
	end

	local function buildActions(slotKey: string): { ContextMenuContext.ContextMenuAction }
		local actions: { ContextMenuContext.ContextMenuAction } = {}

		if item ~= nil then
			local def = ItemDefs[item.Kind]
			if def ~= nil and def.EquipSlots ~= nil then
				for _, equipmentSlot in def.EquipSlots do
					local label = EquipmentTypes.SlotLabels[equipmentSlot] or equipmentSlot
					table.insert(actions, {
						Label = "Equip: " .. label,
						OnSelect = function()
							EquipmentClient.Equip(slotKey, equipmentSlot)
						end,
					})
				end
			end
		end

		table.insert(actions, {
			Label = "Drop",
			OnSelect = function()
				InventoryClient.DropItem(slotKey)
			end,
			Destructive = true,
		})

		return actions
	end

	local function openMenu(screenPos: Vector2)
		local viewport = workspace.CurrentCamera.ViewportSize
		contextMenuContext.OpenContextMenu(
			UDim2.fromScale(screenPos.X / viewport.X, screenPos.Y / viewport.Y),
			buildActions(props.SlotKey)
		)
	end

	return e(Container, {
		Native = {
			ref = slotRef,
			LayoutOrder = props.LayoutOrder,
			BackgroundColor3 = ColorDefs.SlotBackground,
			BackgroundTransparency = if isSource then 0.5 else 0,
			[React.Event.InputBegan] = function(_, input)
				if item == nil then
					return
				end

				local function beginDrag()
					dragContext.BeginDrag(item, "Inventory", props.SlotKey)
				end

				if input.UserInputType == Enum.UserInputType.MouseButton1 and dragContext.DragState == nil then
					DragOrTap.Track({
						StartPos = Vector2.new(input.Position.X, input.Position.Y),
						IsMove = function(i)
							return i.UserInputType == Enum.UserInputType.MouseMovement
						end,
						IsRelease = function(i)
							return i.UserInputType == Enum.UserInputType.MouseButton1
						end,
						Threshold = DRAG_THRESHOLD,
						OnDrag = beginDrag,
						OnTap = function()
							local action = ContextMenuActions.FindClickAction(buildActions(props.SlotKey))
							if action ~= nil then
								action.OnSelect()
							end
						end,
					})
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 and dragContext.DragState == nil then
					openMenu(UserInputService:GetMouseLocation())
				elseif
					input.UserInputType == Enum.UserInputType.Touch
					and input.UserInputState == Enum.UserInputState.Begin
					and dragContext.DragState == nil
				then
					local touchInput = input
					DragOrTap.Track({
						StartPos = Vector2.new(input.Position.X, input.Position.Y),
						IsMove = function(i)
							return i == touchInput
						end,
						IsRelease = function(i)
							return i == touchInput
						end,
						Threshold = DRAG_THRESHOLD,
						OnDrag = beginDrag,
						OnTap = function()
							openMenu(UserInputService:GetMouseLocation())
						end,
					})
				end
			end,
		},
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
			Thickness = 1,
		}),
	})
end

local function Inventory()
	local inventory, setInventory = React.useState({} :: InventoryTypes.Inventory)

	React.useEffect(function()
		return InventoryClient.ObserveInventory(function(inv)
			setInventory(inv)
		end)
	end, {})

	local children: { [string]: any } = {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
		Grid = e(GridLayout, {
			Native = {
				CellSize = UDim2.new(1 / 5, -4, 0, -4),
				CellPadding = UDim2.fromOffset(4, 4),
				FillDirection = Enum.FillDirection.Horizontal,
			},
		}, {
			AspectRatio = e("UIAspectRatioConstraint", {
				AspectRatio = 1,
				AspectType = Enum.AspectType.ScaleWithParentSize,
			}),
		}),
	}

	for i = 1, InventoryTypes.Size do
		local slotKey = tostring(i)
		children["Slot" .. i] = e(InventorySlot, {
			SlotKey = slotKey,
			Item = inventory[slotKey],
			LayoutOrder = i,
		})
	end

	return e(Container, {
		Native = {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		},
	}, children)
end

return Inventory
