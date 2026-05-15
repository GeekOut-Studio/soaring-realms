local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Defs = {
	AxeHit1 = "rbxassetid://87699752991998",
	AxeHit2 = "rbxassetid://70450729382844",
	AxeHit3 = "rbxassetid://109455908786365",
	TreeFall1 = "rbxassetid://122034472338332",
}

return Sift.Dictionary.map(Defs, function(def, kind)
	local sound = Instance.new("Sound")
	sound.Name = kind
	sound.Parent = ReplicatedStorage

	if typeof(def) == "string" then
		sound.SoundId = def
	elseif typeof(def) == "table" then
		for key, val in def do
			sound[key] = val
		end
	else
		error(`Unexpected sound def {kind}`)
	end

	return sound
end)
