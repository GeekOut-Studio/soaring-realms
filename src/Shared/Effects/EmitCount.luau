-- Effect module: emits a one-shot burst from a ParticleEmitter downloaded by path.
-- Resolves the target into a parent the same way as `PlaySound`: a BasePart or
-- Attachment is used directly; a Vector3 or CFrame gets a transient Attachment in
-- `workspace.Effects`. Downloads the emitter via `DownloadClient`, applies `Props`
-- if present, parents to the target with `Enabled = false`, calls `:Emit(Count)`,
-- and cleans up `Lifetime.Max` seconds later so the last particle has time to die.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Trove = require(ReplicatedStorage.Packages.Trove)
local DownloadClient = require(ReplicatedStorage.Shared.Clients.DownloadClient)
local GetEffectsFolder = require(ReplicatedStorage.Shared.GetEffectsFolder)

type Target = Vector3 | CFrame | BasePart | Attachment

return function(args: { Path: string, Target: Target, Count: number, Props: { [string]: any }? })
	local trove = Trove.new()
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

	return DownloadClient.Download(args.Path)
		:andThen(function(downloaded)
			local emitter = downloaded :: ParticleEmitter
			trove:Add(emitter)
			if args.Props ~= nil then
				for key, value in args.Props do
					emitter[key] = value
				end
			end
			emitter.Enabled = false
			emitter.Parent = parent
			emitter:Emit(args.Count)
			return Promise.delay(emitter.Lifetime.Max)
		end)
		:finally(function()
			trove:Destroy()
		end)
end
