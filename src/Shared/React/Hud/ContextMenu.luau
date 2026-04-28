local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local PlatformScale = require(ReplicatedStorage.Shared.React.Common.PlatformScale)
local TextButton = require(ReplicatedStorage.Shared.React.Common.TextButton)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)

local e = React.createElement

local BUTTON_WIDTH = 120
local BUTTON_HEIGHT = 32
local BUTTON_GAP = 2

local function ContextMenu()
	local contextMenuContext = React.useContext(ContextMenuContext.Context)
	local menuState = contextMenuContext.MenuState
	local anchorPoint, setAnchorPoint = React.useState(nil :: Vector2?)
	local panelRef = React.useRef(nil :: Frame?)

	-- Defer reading AbsoluteSize so AutomaticSize has resolved before we check bounds.
	React.useEffect(function()
		if menuState == nil then
			setAnchorPoint(nil)
			return
		end

		local cancelled = false

		task.defer(function()
			if cancelled then
				return
			end
			local panel = panelRef.current
			if panel == nil then
				return
			end

			local viewport = workspace.CurrentCamera.ViewportSize
			local panelSize = panel.AbsoluteSize
			local posX = menuState.Position.X.Scale * viewport.X
			local posY = menuState.Position.Y.Scale * viewport.Y

			local anchorX = if posX + panelSize.X > viewport.X then 1 else 0
			local anchorY = if posY + panelSize.Y > viewport.Y then 1 else 0

			setAnchorPoint(Vector2.new(anchorX, anchorY))
		end)

		return function()
			cancelled = true
		end
	end, { menuState } :: { any })

	-- Close when the user clicks or taps outside the panel. MouseButton2 is excluded
	-- so that right-clicking another slot replaces the menu via OpenContextMenu.
	React.useEffect(function()
		if menuState == nil then
			return
		end

		local playerGui = Players.LocalPlayer.PlayerGui

		local connection = UserInputService.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local objects = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
			local panel = panelRef.current

			for _, obj in objects do
				if obj == panel or (panel ~= nil and obj:IsDescendantOf(panel)) then
					return
				end
			end

			contextMenuContext.CloseContextMenu()
		end)

		return function()
			connection:Disconnect()
		end
	end, { menuState } :: { any })

	if menuState == nil then
		return nil
	end

	local panelChildren: { [string]: any } = {
		Layout = e(VerticalList, {
			Native = { Padding = UDim.new(0, BUTTON_GAP) },
		}),
		Stroke = e("UIStroke", {
			Color = ColorDefs.PanelBorder,
			Thickness = 1,
		}),
	}

	for i, action in menuState.Actions do
		panelChildren["Action" .. i] = e(TextButton, {
			Native = {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
				TextSize = 14,
				Text = action.Label,
				[React.Event.Activated] = function()
					contextMenuContext.CloseContextMenu()
					action.OnSelect()
				end,
			},
		})
	end

	return e("ScreenGui", {
		DisplayOrder = 50,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		PlatformScale = e(PlatformScale),
		Panel = e("Frame", {
			ref = panelRef,
			AnchorPoint = if anchorPoint ~= nil then anchorPoint else Vector2.new(0, 0),
			-- Render far offscreen on the first frame so AutomaticSize can resolve
			-- AbsoluteSize without the user seeing the panel at the wrong anchor.
			-- The deferred effect above measures and then sets `anchorPoint`,
			-- which flips us to the real position on the next render.
			Position = if anchorPoint ~= nil then menuState.Position else UDim2.fromScale(16, 16),
			Size = UDim2.fromOffset(BUTTON_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = ColorDefs.PanelBackground,
			BorderSizePixel = 0,
		}, panelChildren),
	})
end

return ContextMenu
