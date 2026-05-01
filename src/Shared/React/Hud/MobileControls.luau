local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Observers = require(ReplicatedStorage.Packages.Observers)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local FontDefs = require(ReplicatedStorage.Shared.Defs.FontDefs)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local SimpleButton = require(ReplicatedStorage.Shared.React.Common.SimpleButton)
local UseIsMobile = require(ReplicatedStorage.Shared.React.Hooks.UseIsMobile)

local e = React.createElement

local BUTTON_SIZE = 64
local STROKE_THICKNESS = 3
local CORNER_RADIUS = UDim.new(0.5, 0)
local HEIGHT = 68

--[=[
	@within MobileControls
	@function ButtonAt
	@private

	Renders a single mobile control button at the given grid cell.
	@param col number
	@param row number
	@param label string
	@param onActivated () -> ()
	@return React.Element
]=]
local function Button(props: {
	Position: UDim2,
	Label: string,
	OnActivated: () -> (),
})
	return e(SimpleButton, {
		Native = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = props.Position,
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			AutoButtonColor = true,
			[React.Event.Activated] = props.OnActivated,
		},
	}, {
		Corner = e("UICorner", { CornerRadius = CORNER_RADIUS }),
		Stroke = e("UIStroke", {
			Color = ColorDefs.PanelBorder,
			Thickness = STROKE_THICKNESS,
		}),
		Label = e(Label, {
			Native = {
				Text = props.Label,
				FontFace = FontDefs.Bold,
				TextSize = 18,
			},
		}),
	})
end

--[=[
	@class MobileControls
	@client

	Touch-only HUD overlay with Jump / Crouch / Sprint buttons. Renders
	nothing on desktop. Anchored bottom-right and lifted above the
	`Menus` button row so the controls sit just above (and may overlap
	with) any open menu content panel.

	While mounted, hides Roblox's default mobile jump button so the player
	doesn't see two stacked jump buttons.
]=]
local function MobileControls()
	local isMobile = UseIsMobile()
	local outworlderRef = React.useRef(nil :: any)

	React.useEffect(function()
		if not isMobile then
			return
		end
		return Observers.observeCharacter(function(player: Player, character: Model)
			if player ~= Players.LocalPlayer then
				return
			end
			local trove = Trove.new()
			trove:AddPromise(OutworlderClient:WaitForInstance(character):andThen(function(componentInstance)
				outworlderRef.current = componentInstance
			end))
			trove:Add(function()
				outworlderRef.current = nil
			end)
			return trove:WrapClean()
		end)
	end, { isMobile })

	React.useEffect(function()
		if not isMobile then
			return
		end
		local cancelled = false
		local jumpButton: GuiObject? = nil
		task.spawn(function()
			local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
			local touchGui = playerGui:WaitForChild("TouchGui", 10) :: ScreenGui?
			if touchGui == nil or cancelled then
				return
			end
			local frame = touchGui:WaitForChild("TouchControlFrame", 10)
			if frame == nil or cancelled then
				return
			end
			local btn = frame:WaitForChild("JumpButton", 10) :: GuiObject?
			if btn == nil or cancelled then
				return
			end
			jumpButton = btn
			btn.Visible = false
		end)
		return function()
			cancelled = true
			if jumpButton ~= nil then
				jumpButton.Visible = true
			end
		end
	end, { isMobile })

	if not isMobile then
		return nil
	end

	local function onJump()
		local outworlder = outworlderRef.current
		if outworlder ~= nil then
			outworlder:Jump()
		end
	end
	local function onCrouch()
		local outworlder = outworlderRef.current
		if outworlder ~= nil then
			outworlder:ToggleCrouch()
		end
	end
	local function onSprint()
		local outworlder = outworlderRef.current
		if outworlder ~= nil then
			outworlder:ToggleSprint()
		end
	end

	local center = UDim2.new(1, -BUTTON_SIZE * 0.5, 1, -BUTTON_SIZE * 0.5)

	return e(Container, {
		Native = {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -HEIGHT),
			AutomaticSize = Enum.AutomaticSize.XY,
		},
	}, {
		Jump = e(Button, {
			Position = center,
			Label = "Jump",
			OnActivated = onJump,
		}),
		Crouch = e(Button, {
			Position = center + UDim2.fromOffset(-BUTTON_SIZE * 0.75, -BUTTON_SIZE * 1.3),
			Label = "Crouch",
			OnActivated = onCrouch,
		}),
		Sprint = e(Button, {
			Position = center + UDim2.fromOffset(-BUTTON_SIZE * 1.5, 0),
			Label = "Sprint",
			OnActivated = onSprint,
		}),
	})
end

return MobileControls
