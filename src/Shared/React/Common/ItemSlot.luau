local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local DragOrTap = require(ReplicatedStorage.Shared.React.DragOrTap)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local UseDropTargetHover = require(ReplicatedStorage.Shared.React.Hooks.UseDropTargetHover)

local e = React.createElement

local DRAG_THRESHOLD = 10

-- A single visual slot that displays an item and optionally participates in
-- the drag-and-drop system. Used by `Inventory` (full interactivity) and
-- `LootMenu` (drag-source-only, click-to-claim). Behavior knobs:
--
-- - Drag source: set `SlotKey` + `SourceContainer` + non-nil `Item`. The slot
--   begins a drag on press+drag-past-threshold.
-- - Drop target: set `OnDrop`. The slot registers itself under `SlotKey`
--   (which must also be set). Slots without `OnDrop` are source-only.
-- - Tap: `OnTap` fires on a press-and-release-within-threshold (left mouse
--   or single touch). Consumers decide what tap means.
-- - Right-click: `OnAlternate` fires on desktop right-click; mobile has no
--   equivalent gesture in this primitive — consumers can route a touch tap
--   through `OnTap` to whatever "secondary" action they want.
local function ItemSlot(props: {
	Item: InventoryTypes.Item?,
	LayoutOrder: number?,
	SlotKey: string?,
	SourceContainer: string?,
	OnDrop: ((dragItem: DragContext.DragItem) -> ())?,
	OnTap: (() -> ())?,
	OnAlternate: ((screenPos: Vector2) -> ())?,
})
	local dragContext = React.useContext(DragContext.Context)
	local slotRef = React.useRef(nil :: GuiObject?)

	local slotKey = props.SlotKey
	local item = props.Item
	local onDrop = props.OnDrop

	local isSource = slotKey ~= nil
		and dragContext.DragState ~= nil
		and dragContext.DragState.SourceSlot == slotKey
		and dragContext.DragState.SourceContainer == props.SourceContainer
	local isDropHovered = UseDropTargetHover(slotKey or "")

	React.useEffect(function()
		if slotKey == nil or onDrop == nil then
			return
		end
		local instance = slotRef.current
		if instance == nil then
			return
		end

		dragContext.RegisterDropTarget(slotKey, instance, onDrop)
		return function()
			dragContext.UnregisterDropTarget(slotKey, instance)
		end
	end, { slotKey, onDrop } :: { any })

	local text = ""
	if item ~= nil then
		local def = ItemDefs[item.Kind]
		local name = if def ~= nil then def.Name else item.Kind
		text = if item.Count ~= nil then name .. "\n×" .. item.Count else name
	end

	local canDrag = slotKey ~= nil and props.SourceContainer ~= nil and item ~= nil

	return e(Container, {
		Native = {
			ref = slotRef,
			LayoutOrder = props.LayoutOrder,
			BackgroundColor3 = ColorDefs.SlotBackground,
			BackgroundTransparency = if isSource then 0.5 else 0,
			[React.Event.InputBegan] = function(_, input)
				if dragContext.DragState ~= nil then
					return
				end

				local function beginDrag()
					if not canDrag then
						return
					end
					dragContext.BeginDrag(item :: any, props.SourceContainer :: any, slotKey :: any)
				end

				if input.UserInputType == Enum.UserInputType.MouseButton1 then
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
							if props.OnTap ~= nil then
								props.OnTap()
							end
						end,
					})
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
					if props.OnAlternate ~= nil then
						props.OnAlternate(UserInputService:GetMouseLocation())
					end
				elseif
					input.UserInputType == Enum.UserInputType.Touch
					and input.UserInputState == Enum.UserInputState.Begin
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
							if props.OnTap ~= nil then
								props.OnTap()
							end
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
			Color = isDropHovered:map(function(hovered)
				return if hovered then ColorDefs.PanelBorder else ColorDefs.SlotBorder
			end),
			Thickness = isDropHovered:map(function(hovered)
				return if hovered then 3 else 1
			end),
		}),
	})
end

return ItemSlot
