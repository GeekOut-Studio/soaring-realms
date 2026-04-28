local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local GridLayout = require(ReplicatedStorage.Shared.React.Common.GridLayout)
local Image = require(ReplicatedStorage.Shared.React.Common.Image)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local SkillDefs = require(ReplicatedStorage.Shared.Defs.SkillDefs)
local SkillClient = require(ReplicatedStorage.Shared.Clients.SkillClient)
local FontDefs = require(ReplicatedStorage.Shared.Defs.FontDefs)
local FlexFill = require(ReplicatedStorage.Shared.React.Common.FlexFill)
local HorizontalList = require(ReplicatedStorage.Shared.React.Common.HorizontalList)
local PaddingAll = require(ReplicatedStorage.Shared.React.Common.PaddingAll)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)
local SkillExperience = require(ReplicatedStorage.Shared.SkillExperience)
local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

type SkillKind = SkillTypes.SkillKind
type Skill = SkillTypes.Skill

local e = React.createElement

local TILE_HEIGHT = 80
local CELL_GAP = 4

local PROGRESS_BAR_COLOR = Color3.fromRGB(60, 200, 80)
local PROGRESS_BAR_BACKGROUND = Color3.fromRGB(20, 20, 20)

type TileProps = {
	SkillKind: SkillKind,
	Skill: Skill,
	LayoutOrder: number,
}

local function progressFraction(skill: Skill): number
	if skill.Level >= SkillExperience.MaxLevel then
		return 1
	end
	local floor = SkillExperience.ExperienceForLevel(skill.Level)
	local ceiling = SkillExperience.ExperienceForLevel(skill.Level + 1)
	if ceiling <= floor then
		return 1
	end
	return math.clamp((skill.Experience - floor) / (ceiling - floor), 0, 1)
end

local function SkillTile(props: TileProps)
	local def = SkillDefs[props.SkillKind]
	local progress = progressFraction(props.Skill)

	return e(Container, {
		Native = {
			LayoutOrder = props.LayoutOrder,
			BackgroundColor3 = ColorDefs.SlotBackground,
		},
	}, {
		Padding = e(PaddingAll, {
			Padding = UDim.new(0, 2),
		}),
		Layout = e(VerticalList, {
			Native = {
				VerticalFlex = Enum.UIFlexAlignment.SpaceBetween,
			},
		}),
		NameLabel = e(Label, {
			Native = {
				FontFace = FontDefs.Bold,
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 0.3),
				TextColor3 = ColorDefs.TextPrimary,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = def.Name,
				LayoutOrder = 1,
			},
		}),
		Middle = e(Container, {
			Native = {
				Size = UDim2.fromScale(1, 0.5),
				LayoutOrder = 2,
			},
		}, {
			Layout = e(HorizontalList),
			Icon = e(Image, {
				Native = {
					Size = UDim2.fromScale(1, 1),
					SizeConstraint = Enum.SizeConstraint.RelativeYY,
					Image = def.Image,
					LayoutOrder = 1,
				},
			}),
			LevelLabel = e(Label, {
				Native = {
					Size = UDim2.fromScale(0, 1),
					TextColor3 = ColorDefs.TextPrimary,
					TextSize = 22,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = tostring(props.Skill.Level),
					LayoutOrder = 2,
				},
			}, {
				FlexFill = e(FlexFill),
			}),
		}),
		ProgressBar = e("Frame", {
			Size = UDim2.fromScale(1, 0.1),
			BackgroundColor3 = PROGRESS_BAR_BACKGROUND,
			BorderSizePixel = 0,
			LayoutOrder = 3,
		}, {
			Fill = e("Frame", {
				BackgroundColor3 = PROGRESS_BAR_COLOR,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(progress, 1),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = ColorDefs.SlotBorder,
			Thickness = 1,
		}),
	})
end

local function sortedKinds(): { SkillKind }
	local result = table.clone(SkillTypes.Kinds) :: { SkillKind }
	table.sort(result, function(a, b)
		return SkillDefs[a].DisplayOrder < SkillDefs[b].DisplayOrder
	end)
	return result
end

local function Skills()
	local skills, setSkills = React.useState({} :: SkillTypes.Skills)

	React.useEffect(function()
		return SkillClient.ObserveSkills(function(value)
			setSkills(value)
		end)
	end, {})

	local children: { [string]: any } = {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, CELL_GAP),
			PaddingTop = UDim.new(0, CELL_GAP),
			PaddingBottom = UDim.new(0, CELL_GAP),
		}),
		Grid = e(GridLayout, {
			Native = {
				CellSize = UDim2.new(1 / 3, -CELL_GAP, 0, TILE_HEIGHT),
				CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP),
				FillDirection = Enum.FillDirection.Horizontal,
			},
		}),
	}

	for i, kind in sortedKinds() do
		local skill = skills[kind] or { Level = 1, Experience = 0 }
		children["Tile_" .. kind] = e(SkillTile, {
			SkillKind = kind,
			Skill = skill,
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

return Skills
