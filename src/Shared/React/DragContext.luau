local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

local e = React.createElement

--[=[
	@interface DragItem
	@within DragContext
	@field Item InventoryTypes.Item
	@field SourceContainer string
	@field SourceSlot string
]=]
export type DragItem = {
	Item: InventoryTypes.Item,
	SourceContainer: string,
	SourceSlot: string,
}

type RegistryEntry = {
	Id: string,
	OnDrop: (dragItem: DragItem) -> (),
}

--[=[
	@interface DragContextValue
	@within DragContext
	@field DragState DragItem? -- Currently dragged item; nil when idle.
	@field BeginDrag (item: InventoryTypes.Item, sourceContainer: string, sourceSlot: string) -> ()
	@field CancelDrag () -> ()
	@field RegisterDropTarget (id: string, ref: GuiObject, onDrop: (dragItem: DragItem) -> ()) -> ()
	@field UnregisterDropTarget (id: string, ref: GuiObject) -> ()
	@field SubscribeDropTargetHover (id: string, setter: (boolean) -> ()) -> () -> () -- Calls `setter(true)` when `id` becomes the hovered drop target during a drag, and `setter(false)` when it stops. Returns an unsubscribe function. Prefer the `UseDropTargetHover` hook over calling this directly.
]=]
export type DragContextValue = {
	DragState: DragItem?,
	BeginDrag: (item: InventoryTypes.Item, sourceContainer: string, sourceSlot: string) -> (),
	CancelDrag: () -> (),
	RegisterDropTarget: (id: string, ref: GuiObject, onDrop: (dragItem: DragItem) -> ()) -> (),
	UnregisterDropTarget: (id: string, ref: GuiObject) -> (),
	SubscribeDropTargetHover: (id: string, setter: (boolean) -> ()) -> () -> (),
}

local defaultValue: DragContextValue = {
	DragState = nil,
	BeginDrag = function() end,
	CancelDrag = function() end,
	RegisterDropTarget = function() end,
	UnregisterDropTarget = function() end,
	SubscribeDropTargetHover = function()
		return function() end
	end,
}

--[=[
	@class DragContext
	React context and provider for inventory drag-and-drop state.
	Drop targets register their own OnDrop callbacks; the provider mediates
	between draggable items and registered targets via GetGuiObjectsAtPosition.
]=]

--[=[
	@prop Context React.Context<DragContextValue>
	@within DragContext
	The React context consumed by draggables and drop targets.
]=]
local Context = React.createContext(defaultValue)

--[=[
	@within DragContext
	Provider component that owns drag state and the drop-target registry.
	Wrap any subtree containing draggables or drop targets in a single Provider.
	@param props { children: any }
]=]
local function Provider(props: { children: any })
	local dragState, setDragState = React.useState(nil :: DragItem?)
	local hoveredEntry = React.useRef(nil :: RegistryEntry?)
	local instanceMap = React.useRef({} :: { [GuiObject]: RegistryEntry })
	local hoverSubscribers = React.useRef({} :: { [string]: (boolean) -> () })

	-- Notifies hover subscribers when the hovered drop target changes. Reads
	-- and writes `hoveredEntry.current` so callers don't have to track the
	-- transition themselves.
	local function setHoveredEntry(newEntry: RegistryEntry?)
		local prev = hoveredEntry.current
		if prev == newEntry then
			return
		end
		hoveredEntry.current = newEntry
		local prevId = if prev ~= nil then prev.Id else nil
		local newId = if newEntry ~= nil then newEntry.Id else nil
		if prevId == newId then
			return
		end
		if prevId ~= nil then
			local setter = hoverSubscribers.current[prevId]
			if setter ~= nil then
				setter(false)
			end
		end
		if newId ~= nil then
			local setter = hoverSubscribers.current[newId]
			if setter ~= nil then
				setter(true)
			end
		end
	end

	local beginDrag = React.useCallback(function(item, sourceContainer, sourceSlot)
		setDragState({
			Item = item,
			SourceContainer = sourceContainer,
			SourceSlot = sourceSlot,
		})
	end, {})

	local cancelDrag = React.useCallback(function()
		setDragState(nil)
		setHoveredEntry(nil)
	end, {})

	local registerDropTarget = React.useCallback(function(id, instance, onDrop)
		instanceMap.current[instance] = { Id = id, OnDrop = onDrop }
	end, {})

	local unregisterDropTarget = React.useCallback(function(_id, instance)
		local entry = instanceMap.current[instance]
		if entry ~= nil and hoveredEntry.current == entry then
			setHoveredEntry(nil)
		end
		instanceMap.current[instance] = nil
	end, {})

	local subscribeDropTargetHover = React.useCallback(function(id, setter)
		hoverSubscribers.current[id] = setter
		return function()
			if hoverSubscribers.current[id] == setter then
				hoverSubscribers.current[id] = nil
			end
		end
	end, {})

	local contextValue = React.useMemo(
		function(): DragContextValue
			return {
				DragState = dragState,
				BeginDrag = beginDrag,
				CancelDrag = cancelDrag,
				RegisterDropTarget = registerDropTarget,
				UnregisterDropTarget = unregisterDropTarget,
				SubscribeDropTargetHover = subscribeDropTargetHover,
			}
		end,
		{
			dragState,
			beginDrag,
			cancelDrag,
			registerDropTarget,
			unregisterDropTarget,
			subscribeDropTargetHover,
		} :: { any }
	)

	React.useEffect(function()
		if dragState == nil then
			return
		end

		local playerGui = Players.LocalPlayer.PlayerGui

		local movedConnection = UserInputService.InputChanged:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local objects = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
			local found: RegistryEntry? = nil
			for _, obj in objects do
				local entry = instanceMap.current[obj]
				if entry ~= nil then
					found = entry
					break
				end
			end
			setHoveredEntry(found)
		end)

		local endedConnection = UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			-- Clear drag state BEFORE OnDrop — it can yield (RPC), and a trailing
			-- `setDragState(nil)` after a yield risks getting lost if the tree
			-- unmounts mid-yield, stranding the preview on the cursor.
			local entry = hoveredEntry.current
			local pending = dragState
			setHoveredEntry(nil)
			setDragState(nil)
			if entry ~= nil then
				entry.OnDrop(pending)
			end
		end)

		return function()
			movedConnection:Disconnect()
			endedConnection:Disconnect()
			setHoveredEntry(nil)
		end
	end, { dragState } :: { any })

	return e(Context.Provider, { value = contextValue }, props.children)
end

return {
	Context = Context,
	Provider = Provider,
}
