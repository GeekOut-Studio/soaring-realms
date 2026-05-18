local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Observers = require(ReplicatedStorage.Packages.Observers)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local DialogueContext = require(ReplicatedStorage.Shared.React.DialogueContext)
local HorizontalList = require(ReplicatedStorage.Shared.React.Common.HorizontalList)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)
local PaddingAll = require(ReplicatedStorage.Shared.React.Common.PaddingAll)
local Panel = require(ReplicatedStorage.Shared.React.Common.Panel)
local TextButton = require(ReplicatedStorage.Shared.React.Common.TextButton)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)

local e = React.createElement

local PANEL_WIDTH = 360

local function Dialogue()
	local dialogueContext = React.useContext(DialogueContext.Context)
	local showMessage = dialogueContext.ShowMessage

	-- Subscribe the local player's ActionFailed signal into the context. Sized
	-- via the same observe-character / WaitForInstance pattern as the Hotbar's
	-- stamina/health bindings; cleaned up via Trove when the local character
	-- respawns.
	React.useEffect(function()
		return Observers.observeCharacter(function(player: Player, character: Model)
			if player ~= Players.LocalPlayer then
				return
			end
			local trove = Trove.new()
			trove:AddPromise(OutworlderClient:WaitForInstance(character):andThen(function(componentInstance)
				trove:Add(componentInstance.ActionFailedSignal:Connect(function(message: string)
					showMessage(message)
				end))
			end))
			return trove:WrapClean()
		end)
	end, { showMessage } :: { any })

	if dialogueContext.Message == nil then
		return nil
	end

	return e(Panel, {
		Native = {
			Active = true,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromOffset(PANEL_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = ColorDefs.PanelBackground,
			ZIndex = 65,
		},
	}, {
		Stroke = e("UIStroke", {
			Color = ColorDefs.PanelBorder,
			Thickness = 2,
		}),
		Padding = e(PaddingAll, {
			Padding = UDim.new(0, 8),
		}),
		Layout = e(VerticalList, {
			Native = {
				Padding = UDim.new(0, 8),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
			},
		}),
		Body = e(Label, {
			Native = {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = dialogueContext.Message,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			},
		}),
		Footer = e(Container, {
			Native = {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			},
		}, {
			Layout = e(HorizontalList, {
				Native = {
					Padding = UDim.new(0, 4),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				},
			}),
			Okay = e(TextButton, {
				Native = {
					Size = UDim2.fromScale(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Text = "OK",
					TextSize = 20,
					[React.Event.Activated] = function()
						dialogueContext.Dismiss()
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

return Dialogue
