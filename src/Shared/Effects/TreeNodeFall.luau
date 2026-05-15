-- Effect module: animates a TreeNode's trunk from its standing pose to the stump's
-- FallenTrunkAttachment pose over `Duration` seconds, dragging `Top` along at the
-- fixed offset captured at the start of the fall. Expects the standard TreeNode
-- hierarchy: `Stump` (BasePart with `FallenTrunkAttachment`), `Trunk` (BasePart
-- with `BaseAttachment`), and `Top` (PVInstance) under `Model`. Lerps the
-- BaseAttachment's WorldCFrame and back-solves trunk.CFrame each frame, so the
-- trunk rotates about its base.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GetEffectsFolder = require(ReplicatedStorage.Shared.GetEffectsFolder)
local Timeline = require(ReplicatedStorage.Shared.Timeline)

return function(args: { Model: Model, Duration: number })
	local stump = args.Model:FindFirstChild("Stump") :: BasePart
	local trunk = args.Model:FindFirstChild("Trunk") :: BasePart
	local topTemplate = args.Model:FindFirstChild("Top") :: PVInstance
	local top = topTemplate:Clone()
	top.Parent = GetEffectsFolder()
	topTemplate.Parent = nil
	local fallenAttachment = stump:FindFirstChild("FallenTrunkAttachment") :: Attachment
	local baseAttachment = trunk:FindFirstChild("BaseAttachment") :: Attachment

	local startWorldCFrame = baseAttachment.WorldCFrame
	local endWorldCFrame = fallenAttachment.WorldCFrame
	local baseLocalInverse = baseAttachment.CFrame:Inverse()
	local topRelativeToTrunk = trunk.CFrame:Inverse() * top:GetPivot()

	Timeline(args.Duration, function(alphaRaw)
		local alpha = math.pow(alphaRaw, 4)
		local newTrunkCFrame = startWorldCFrame:Lerp(endWorldCFrame, alpha) * baseLocalInverse
		trunk.CFrame = newTrunkCFrame
		top:PivotTo(newTrunkCFrame * topRelativeToTrunk)
	end):andThen(function()
		local entries: { [BasePart]: number } = {}
		for _, object in top:GetDescendants() do
			if object:IsA("BasePart") then
				entries[object] = object.Transparency
			end
		end
		return Timeline(1, function(alpha)
			for part, startingTransparency in entries do
				part.Transparency = math.lerp(startingTransparency, 1, alpha)
			end
		end)
	end):andThen(function()
		top:Destroy()
	end)
end
