local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local GridLayout = require(ReplicatedStorage.Shared.React.Common.GridLayout)
local HorizontalList = require(ReplicatedStorage.Shared.React.Common.HorizontalList)
local ItemSlot = require(ReplicatedStorage.Shared.React.Common.ItemSlot)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local TextButton = require(ReplicatedStorage.Shared.React.Common.TextButton)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local LootClient = require(ReplicatedStorage.Shared.Clients.LootClient)
local FontDefs = require(ReplicatedStorage.Shared.Defs.FontDefs)
local LootTypes = require(ReplicatedStorage.Shared.Types.LootTypes)
local MenusContext = require(ReplicatedStorage.Shared.React.MenusContext)
local Observing = require(ReplicatedStorage.Shared.Observing)
local Range = require(ReplicatedStorage.Shared.Range)
local Aspect = require(ReplicatedStorage.Shared.React.Common.Aspect)
local FlexFill = require(ReplicatedStorage.Shared.React.Common.FlexFill)
local PaddingAll = require(ReplicatedStorage.Shared.React.Common.PaddingAll)
local Panel = require(ReplicatedStorage.Shared.React.Common.Panel)
local UsePlatform = require(ReplicatedStorage.Shared.React.Hooks.UsePlatform)

type PlayerLoot = LootTypes.PlayerLoot

local e = React.createElement

local function LootMenu()
	local menusContext = React.useContext(MenusContext.Context)
	local platform = UsePlatform()
	local bag, setBag = React.useState(LootClient.GetOpenedBag())
	local loot, setLoot = React.useState(nil :: PlayerLoot?)

	React.useEffect(function()
		local conn = LootClient.OpenedBagChanged:Connect(function(newBag)
			setBag(newBag)
		end)
		-- Re-sync in case OpenBag fired between mount and effect.
		setBag(LootClient.GetOpenedBag())
		return function()
			conn:Disconnect()
		end
	end, {})

	React.useEffect(function()
		if bag == nil then
			setLoot(nil)
			return
		end
		-- Seed synchronously so the first render after open already has a value;
		-- subsequent updates flow through the Observe.
		setLoot(bag.LootProperty:Get())
		return Observing.observeCommProperty(bag.LootProperty, function(newLoot: PlayerLoot?)
			setLoot(newLoot)
			return nil
		end)
	end, { bag } :: { any })

	React.useEffect(function()
		if bag == nil then
			return
		end
		menusContext.SetForcedMenu("Inventory")
		return function()
			menusContext.SetForcedMenu(nil)
		end
	end, { bag } :: { any })

	if bag == nil or loot == nil then
		return nil
	end

	local isPhone = platform == "Phone"
	local anchorPoint = if isPhone then Vector2.new(0, 0) else Vector2.new(0.5, 0.5)
	local position
	if isPhone then
		local inset = GuiService:GetGuiInset()
		position = UDim2.fromOffset(inset.X + 8, inset.Y + 8)
	else
		position = UDim2.fromScale(0.5, 0.5)
	end

	return e(Panel, {
		Native = {
			Active = true,
			AnchorPoint = anchorPoint,
			Position = position,
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = ColorDefs.PanelBackground,
			ZIndex = 128,
		},
	}, {
		Stroke = e("UIStroke", {
			Color = ColorDefs.PanelBorder,
			Thickness = 2,
		}),
		Padding = e(PaddingAll, {
			Padding = UDim.new(0, 4),
		}),
		Layout = e(VerticalList, {
			Native = {
				Padding = UDim.new(0, 4),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
			},
		}),

		Header = e(Container, {
			Native = {
				LayoutOrder = 1,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			},
		}, {
			Layout = e(HorizontalList, {
				Native = {
					Padding = UDim.new(0, 4),
					ItemLineAlignment = Enum.ItemLineAlignment.Stretch,
				},
			}),
			Title = e(Label, {
				Native = {
					LayoutOrder = 1,
					Size = UDim2.fromScale(1, 0),
					Text = "Loot",
					TextXAlignment = Enum.TextXAlignment.Left,
					TextSize = 30,
					FontFace = FontDefs.Bold,
					AutomaticSize = Enum.AutomaticSize.Y,
				},
			}, {
				Flex = e(FlexFill),
			}),
			Close = e(TextButton, {
				Native = {
					LayoutOrder = 2,
					Size = UDim2.fromScale(0, 0),
					Text = "X",
					TextSize = 20,
					FontFace = FontDefs.Bold,
					[React.Event.Activated] = function()
						LootClient.CloseBag()
					end,
				},
			}, {
				Stroke = e("UIStroke", {
					Color = ColorDefs.PanelBorder,
					Thickness = 1,
				}),
				Aspect = e(Aspect, {
					Ratio = 1,
				}),
			}),
		}),
		Slots = e(Container, {
			Native = {
				LayoutOrder = 2,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
			},
		}, {
			Layout = e(GridLayout, {
				Native = {
					CellSize = UDim2.fromOffset(64, 64),
					CellPadding = UDim2.fromOffset(4, 4),
					FillDirectionMaxCells = 6,
				},
			}),
			Content = e(
				React.Fragment,
				nil,
				Sift.Dictionary.map(Range(math.max(12, #loot)), function(index)
					local item = loot[index]
					if item ~= nil then
						return e(ItemSlot, {
							Item = item,
							LayoutOrder = index,
							SlotKey = "LootBag:" .. tostring(index),
							SourceContainer = "LootBag",
							OnTap = function()
								LootClient.ClaimOne(index)
							end,
						}),
							`Slot{index}`
					else
						return e(Container, {
							Native = {
								LayoutOrder = index,
							},
						}),
							`Slot{index}`
					end
				end)
			),
		}),
		Footer = e(Container, {
			Native = {
				LayoutOrder = 3,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			},
		}, {
			Layout = e(HorizontalList, {
				Native = {
					Padding = UDim.new(0, 4),
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
				},
			}),
			LootAll = e(TextButton, {
				Native = {
					LayoutOrder = 1,
					Size = UDim2.fromScale(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Text = "Loot All",
					TextSize = 24,
					[React.Event.Activated] = function()
						LootClient.ClaimAll()
					end,
				},
			}, {
				Padding = e(PaddingAll, {
					Padding = UDim.new(0, 8),
				}),
				Stroke = e("UIStroke", {
					Color = ColorDefs.PanelBorder,
					Thickness = 1,
				}),
			}),
		}),
	})
end

return LootMenu
