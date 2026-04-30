--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

export type AnimationKind = "CrouchIdle" | "CrouchWalk"

local Defs: { [AnimationKind]: number } = {
	CrouchIdle = 90752562165133,
	CrouchWalk = 96011308580698,
}

local function transform(defs: { [AnimationKind]: number }): { [AnimationKind]: Animation }
	return Sift.Dictionary.map(defs, function(id, kind)
		local animation = Instance.new("Animation")
		animation.Name = kind
		animation.AnimationId = `rbxassetid://{id}`
		return animation
	end)
end

return transform(Defs)
