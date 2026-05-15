-- Effect module: plays a sound from `SoundDefs` at a world location or on an existing instance.
-- `target` can be a BasePart/Attachment (sound is parented directly to it) or a Vector3/CFrame
-- (a transient Attachment is created in `workspace.Effects` to host the sound). All transient
-- instances are cleaned up when the sound ends. Assumes non-looping sounds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Trove = require(ReplicatedStorage.Packages.Trove)
local SoundDefs = require(ReplicatedStorage.Shared.Defs.SoundDefs)
local GetEffectsFolder = require(ReplicatedStorage.Shared.GetEffectsFolder)

type Target = Vector3 | CFrame | BasePart | Attachment

local LOAD_TIMEOUT = 5

return function(args: { Target: Target, Kind: string, Props: { [string]: any }? })
	local template = SoundDefs[args.Kind]
	if template == nil then
		warn(`PlaySound: unknown soundKind {args.Kind}`)
		return
	end

	local trove = Trove.new()
	local sound = trove:Clone(template)

	if args.Props ~= nil then
		for key, value in args.Props do
			sound[key] = value
		end
	end

	local target = args.Target
	local parent: Instance
	if typeof(target) == "Instance" then
		parent = target
	else
		local attachment = trove:Construct(Instance.new, "Attachment")
		if typeof(target) == "Vector3" then
			attachment.WorldCFrame = CFrame.new(target)
		else
			attachment.WorldCFrame = target
		end
		attachment.Parent = GetEffectsFolder()
		parent = attachment
	end

	sound.Parent = parent

	local loadPromise = if sound.IsLoaded
		then Promise.resolve()
		else Promise.fromEvent(sound.Loaded):timeout(LOAD_TIMEOUT)

	trove:AddPromise(loadPromise)

	loadPromise
		:andThen(function()
			sound:Play()
			trove:Connect(sound.Ended, function()
				trove:Destroy()
			end)
		end)
		:catch(function()
			trove:Destroy()
		end)
end
