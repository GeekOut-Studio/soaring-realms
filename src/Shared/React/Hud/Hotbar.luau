local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Observers = require(ReplicatedStorage.Packages.Observers)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ActionProgressBar = require(ReplicatedStorage.Shared.React.Hud.ActionProgressBar)
local AbilityClient = require(ReplicatedStorage.Shared.Clients.AbilityClient)
local AbilityDefs = require(ReplicatedStorage.Shared.Defs.AbilityDefs)
local AbilityShared = require(ReplicatedStorage.Shared.AbilityShared)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local HealthTypes = require(ReplicatedStorage.Shared.Types.HealthTypes)
local HorizontalList = require(ReplicatedStorage.Shared.React.Common.HorizontalList)
local HotbarClient = require(ReplicatedStorage.Shared.Clients.HotbarClient)
local HotbarTypes = require(ReplicatedStorage.Shared.Types.HotbarTypes)
local InventoryClient = require(ReplicatedStorage.Shared.Clients.InventoryClient)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)
local Observing = require(ReplicatedStorage.Shared.Observing)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)
local UseDropTargetHover = require(ReplicatedStorage.Shared.React.Hooks.UseDropTargetHover)
local UseHotbar = require(ReplicatedStorage.Shared.React.Hooks.UseHotbar)
local UsePlatform = require(ReplicatedStorage.Shared.React.Hooks.UsePlatform)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)

type Inventory = InventoryTypes.Inventory
type HotbarBinding = HotbarTypes.HotbarBinding
type DragItem = DragContext.DragItem

local e = React.createElement

local PADDING = UDim.new(0, 4)
local BAR_HEIGHT = 10
local BUTTON_SIZE = 56
-- Sized to match the height of the center column: the buttons row (`BUTTON_SIZE`)
-- plus one bar's worth of header. We intentionally only count one of the two
-- bars so the MainHand slot is taller than the buttons but doesn't stretch to
-- cover both stamina and health — keeps it visually grouped with the row.
local SPECIAL_BUTTON_SIZE = BUTTON_SIZE + PADDING.Offset + BAR_HEIGHT

-- Builds the human-readable label for a binding. Falls back to the raw kind
-- string when a def is missing so debugging an unknown binding shows the kind
-- rather than a blank slot.
local function describeBinding(binding: HotbarBinding): string
	if binding.Kind == "Empty" then
		return ""
	elseif binding.Kind == "Ability" then
		local def = AbilityDefs[binding.AbilityKind]
		return if def ~= nil then def.Name else binding.AbilityKind
	elseif binding.Kind == "Item" then
		local def = ItemDefs[binding.ItemKind]
		local name = if def ~= nil then def.Name else binding.ItemKind
		local action = binding.Action
		local suffix: string
		if action.Kind == "Equip" then
			local label = EquipmentTypes.SlotLabels[action.Slot] or action.Slot
			suffix = `Equip {label}`
		else
			suffix = action.Kind
		end
		return `{name}\n{suffix}`
	end
	return ""
end

local function inventoryHasKind(inventory: Inventory, itemKind: string): boolean
	for i = 1, InventoryTypes.Size do
		local item = inventory[tostring(i)]
		if item ~= nil and item.Kind == itemKind then
			return true
		end
	end
	return false
end

-- Returns the AbilityDef's cooldown group, or nil when the binding doesn't
-- map to a known ability — in which case the slot has no cooldown overlay.
local function getCooldownGroup(binding: HotbarBinding): string?
	if binding.Kind ~= "Ability" then
		return nil
	end
	local def = AbilityDefs[binding.AbilityKind]
	if def == nil then
		return nil
	end
	return AbilityShared.GetCooldownGroup(def)
end

local function isBindingAvailable(binding: HotbarBinding, inventory: Inventory): boolean
	if binding.Kind == "Empty" then
		return false
	elseif binding.Kind == "Ability" then
		return AbilityDefs[binding.AbilityKind] ~= nil
	elseif binding.Kind == "Item" then
		return inventoryHasKind(inventory, binding.ItemKind)
	end
	return false
end

-- Builds the context-menu actions offered after dropping an item onto a slot:
-- one "Equip: <slot>" per equip-slot the item supports, plus "Drop".
local function buildBindActionsForItem(
	slotKey: string,
	item: InventoryTypes.Item
): { ContextMenuContext.ContextMenuAction }
	local actions: { ContextMenuContext.ContextMenuAction } = {}
	local def = ItemDefs[item.Kind]
	if def ~= nil and def.EquipSlots ~= nil then
		for _, equipmentSlot in def.EquipSlots do
			local label = EquipmentTypes.SlotLabels[equipmentSlot] or equipmentSlot
			local capturedSlot: EquipmentTypes.EquipmentSlot = equipmentSlot
			table.insert(actions, {
				Label = `Bind: Equip {label}`,
				OnSelect = function()
					HotbarClient.SetBinding(slotKey, {
						Kind = "Item",
						ItemKind = item.Kind,
						Action = { Kind = "Equip", Slot = capturedSlot },
					})
				end,
			})
		end
	end
	table.insert(actions, {
		Label = "Bind: Drop",
		OnSelect = function()
			HotbarClient.SetBinding(slotKey, {
				Kind = "Item",
				ItemKind = item.Kind,
				Action = { Kind = "Drop" },
			})
		end,
	})
	return actions
end

local HotbarSlot = React.memo(function(props: {
	SlotKey: string,
	Binding: HotbarBinding,
	Inventory: Inventory,
	CooldownExpiresAt: number,
	LayoutOrder: number?,
	Size: UDim2,
})
	local binding = props.Binding
	local dragContext = React.useContext(DragContext.Context)
	local contextMenuContext = React.useContext(ContextMenuContext.Context)
	local slotRef = React.useRef(nil :: GuiObject?)
	local isMainHand = props.SlotKey == HotbarTypes.MainHandSlotKey
	-- Drives a hover-highlight via the Stroke binding below. MainHand isn't a
	-- registered drop target so its hook always reads false; harmless.
	local isDropHovered = UseDropTargetHover(props.SlotKey)

	-- MainHand is server-managed; refuse drops. Configurable slots accept any
	-- inventory drag and open the bind-action picker so the player chooses
	-- which item action to bind.
	React.useEffect(function()
		if isMainHand then
			return
		end
		local instance = slotRef.current
		if instance == nil then
			return
		end

		dragContext.RegisterDropTarget(props.SlotKey, instance, function(dragItem: DragItem)
			if dragItem.SourceContainer ~= "Inventory" then
				return
			end
			local viewport = Workspace.CurrentCamera.ViewportSize
			local mousePos = UserInputService:GetMouseLocation()
			contextMenuContext.OpenContextMenu(
				UDim2.fromScale(mousePos.X / viewport.X, mousePos.Y / viewport.Y),
				buildBindActionsForItem(props.SlotKey, dragItem.Item)
			)
		end)

		return function()
			dragContext.UnregisterDropTarget(props.SlotKey, instance)
		end
	end, { isMainHand, props.SlotKey } :: { any })

	local function openUnbindMenu(screenPos: Vector2)
		if isMainHand or binding.Kind == "Empty" then
			return
		end
		local viewport = Workspace.CurrentCamera.ViewportSize
		contextMenuContext.OpenContextMenu(UDim2.fromScale(screenPos.X / viewport.X, screenPos.Y / viewport.Y), {
			{
				Label = "Unbind",
				OnSelect = function()
					HotbarClient.ClearBinding(props.SlotKey)
				end,
				Destructive = true,
			},
		})
	end

	-- Cooldown progress as a 0..1 alpha (1 = full cooldown remaining, 0 = ready).
	-- Held in a `useBinding` so per-frame updates flow straight into the
	-- overlay's mapped Size/Visible without re-rendering the slot. The
	-- RenderStepped handler self-disconnects the frame the cooldown expires,
	-- so an idle slot has zero per-frame overhead.
	local expiresAt = props.CooldownExpiresAt
	local cooldownDuration = 0
	if binding.Kind == "Ability" then
		local def = AbilityDefs[binding.AbilityKind]
		if def ~= nil then
			cooldownDuration = def.Cooldown
		end
	end

	local cooldownAlpha, setCooldownAlpha = React.useBinding(0)
	React.useEffect(function()
		local nowSeconds = Workspace:GetServerTimeNow()
		if expiresAt <= nowSeconds or cooldownDuration <= 0 then
			setCooldownAlpha(0)
			return
		end
		setCooldownAlpha(math.clamp((expiresAt - nowSeconds) / cooldownDuration, 0, 1))
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local current = Workspace:GetServerTimeNow()
			local remaining = expiresAt - current
			if remaining <= 0 then
				setCooldownAlpha(0)
				conn:Disconnect()
				return
			end
			setCooldownAlpha(math.clamp(remaining / cooldownDuration, 0, 1))
		end)
		return function()
			conn:Disconnect()
		end
	end, { expiresAt, cooldownDuration })

	local cooldownSize = cooldownAlpha:map(function(alpha)
		return UDim2.fromScale(1, alpha)
	end)
	local cooldownVisible = cooldownAlpha:map(function(alpha)
		return alpha > 0
	end)

	local available = isBindingAvailable(binding, props.Inventory)
	local textTransparency = if binding.Kind == "Empty" then 1 elseif available then 0 else 0.5

	return e("Frame", {
		ref = slotRef,
		LayoutOrder = props.LayoutOrder,
		Size = props.Size,
		BackgroundColor3 = ColorDefs.SlotBackground,
		BorderSizePixel = 0,
		Active = binding.Kind ~= "Empty",
		[React.Event.InputBegan] = function(_, input)
			local isActivate = input.UserInputType == Enum.UserInputType.MouseButton1
				or (
					input.UserInputType == Enum.UserInputType.Touch
					and input.UserInputState == Enum.UserInputState.Begin
				)
			if isActivate then
				if binding.Kind ~= "Empty" then
					HotbarClient.Activate(props.SlotKey)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				openUnbindMenu(UserInputService:GetMouseLocation())
			end
		end,
	}, {
		ItemLabel = e(Label, {
			Native = {
				TextColor3 = ColorDefs.TextPrimary,
				TextSize = 13,
				TextWrapped = true,
				TextTransparency = textTransparency,
				Text = describeBinding(binding),
			},
		}),
		CooldownOverlay = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = cooldownSize,
			Visible = cooldownVisible,
			BackgroundColor3 = ColorDefs.Black,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),
		Stroke = e("UIStroke", {
			Color = isDropHovered:map(function(hovered)
				if hovered then
					return ColorDefs.PanelBorder
				end
				return if isMainHand then ColorDefs.PanelBorder else ColorDefs.SlotBorder
			end),
			Thickness = isDropHovered:map(function(hovered)
				if hovered then
					return 3
				end
				return if isMainHand then 2 else 1
			end),
		}),
	})
end)

local function Hotbar()
	local isPhone = UsePlatform() == "Phone"
	local stamina, setStamina = React.useState(MovementTypes.MaxStamina)
	local maxStamina, setMaxStamina = React.useState(MovementTypes.MaxStamina)
	local health, setHealth = React.useState(HealthTypes.DefaultMaxHealth)
	local maxHealth, setMaxHealth = React.useState(HealthTypes.DefaultMaxHealth)
	local hotbar = UseHotbar()
	local inventory, setInventory = React.useState({} :: Inventory)
	local cooldowns, setCooldowns = React.useState({} :: { [string]: number })

	React.useEffect(function()
		return AbilityClient.ObserveCooldowns(function(value)
			setCooldowns(value)
		end)
	end, {})

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
				trove:Add(Observing.observeCommProperty(componentInstance.HealthProperty, setHealth))
				trove:Add(Observing.observeCommProperty(componentInstance.MaxHealthProperty, setMaxHealth))
			end))
			return trove:WrapClean()
		end)
	end, {})

	React.useEffect(function()
		return InventoryClient.ObserveInventory(function(value)
			setInventory(value)
		end)
	end, {})

	local staminaFraction = math.clamp(stamina / maxStamina, 0, 1)
	local healthFraction = math.clamp(health / maxHealth, 0, 1)

	local function expiresAtFor(binding: HotbarBinding): number
		local group = getCooldownGroup(binding)
		return if group ~= nil then cooldowns[group] or 0 else 0
	end

	local numberedSlots: { [string]: any } = {}
	for i, slotKey in HotbarTypes.ConfigurableSlotKeys do
		local slotBinding = hotbar.Bindings[slotKey] or HotbarTypes.EmptyBinding
		numberedSlots["Slot_" .. slotKey] = e(HotbarSlot, {
			SlotKey = slotKey,
			Binding = slotBinding,
			Inventory = inventory,
			CooldownExpiresAt = expiresAtFor(slotBinding),
			LayoutOrder = i,
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		})
	end

	local mainHandBinding = hotbar.Bindings[HotbarTypes.MainHandSlotKey] or HotbarTypes.EmptyBinding

	return e(Container, {
		Native = {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			AnchorPoint = if isPhone then Vector2.new(0, 1) else Vector2.new(0.5, 1),
			Position = if isPhone then UDim2.fromScale(0, 1) else UDim2.fromScale(0.5, 1),
		},
	}, {
		Layout = e(HorizontalList, {
			Native = {
				Padding = PADDING,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			},
		}),
		Left = e(Container, {
			Native = {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(SPECIAL_BUTTON_SIZE, SPECIAL_BUTTON_SIZE),
				BorderSizePixel = 0,
			},
		}, {
			MainHand = if mainHandBinding.Kind == "Empty"
				then nil
				else e(HotbarSlot, {
					SlotKey = HotbarTypes.MainHandSlotKey,
					Binding = mainHandBinding,
					Inventory = inventory,
					CooldownExpiresAt = expiresAtFor(mainHandBinding),
					Size = UDim2.fromScale(1, 1),
				}),
		}),
		-- Empty mirror of the Left container so the Center column stays
		-- horizontally centered under AutomaticSize, regardless of whether
		-- the MainHand slot is rendered.
		RightSpacer = e(Container, {
			Native = {
				LayoutOrder = 3,
				Size = UDim2.fromOffset(SPECIAL_BUTTON_SIZE, SPECIAL_BUTTON_SIZE),
				BorderSizePixel = 0,
			},
		}),
		Center = e(Container, {
			Native = {
				LayoutOrder = 2,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
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
				Slots = e(React.Fragment, nil, numberedSlots),
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
		}),
	})
end

return Hotbar
