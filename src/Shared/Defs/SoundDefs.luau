local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Defs = {
	AxeHit1 = "rbxassetid://87699752991998",
	AxeHit2 = "rbxassetid://70450729382844",
	AxeHit3 = "rbxassetid://109455908786365",
	FishingCatch1 = "rbxassetid://92738565434854",
	FishingCatch2 = "rbxassetid://87975563650352",
	FishingCatch3 = "rbxassetid://122637661377436",
	FishingCatch4 = "rbxassetid://122896433933377",
	FishingRodCast1 = "rbxassetid://82346821122167",
	FishingRodLand1 = "rbxassetid://137702813725211",
	FishingRodLand2 = "rbxassetid://76618932653162",
	FishingRodLand3 = "rbxassetid://105417080667480",
	FishingRodLand4 = "rbxassetid://110545855543470",
	FishingSpotFrenzy1 = "rbxassetid://103021287750788",
	FishingSpotFrenzy2 = "rbxassetid://108974327964352",
	FishingSpotFrenzy3 = "rbxassetid://105719373779458",
	FishingSpotFrenzy4 = "rbxassetid://114439677556834",
	FishingSpotFrenzyLoop1 = {
		SoundId = "rbxassetid://132066512752627",
		Looped = true,
		Volume = 0.1,
	},
	OreBreak1 = "rbxassetid://74542421768481",
	PickaxeHit1 = "rbxassetid://84606356648769",
	PickaxeHit2 = "rbxassetid://86353294574002",
	PickaxeHit3 = "rbxassetid://93990502023598",
	PickaxeHit4 = "rbxassetid://86565841939766",
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
