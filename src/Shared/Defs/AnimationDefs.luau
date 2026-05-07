--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Defs: { [string]: number } = {
	CrouchIdle = 90752562165133,
	CrouchWalk = 96011308580698,
	ToolOverheadSwing = 134572391725643,
	ToolShoulderedIdle = 125738314234655,
	ImpIdle = 135155347546291,
}

local function transform(defs: { [string]: number }): { [string]: Animation }
	return Sift.Dictionary.map(defs, function(id, kind)
		local animation = Instance.new("Animation")
		animation.Name = kind
		animation.AnimationId = `rbxassetid://{id}`
		return animation
	end)
end

return transform(Defs)
