-- Effect module: animates each bonus model under `Model.Bonus` from the ore node's
-- center pivot out to that bonus model's original pivot over `Duration` seconds.
-- Awaits the server-provided `BonusManifest` of the bonus folder so every bonus
-- model and its descendants are guaranteed to be fully replicated before we read
-- pivots — sidesteps the replication race where `ChildAdded` fires the moment a
-- model is parented but its parts trickle in over the following frames.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectClient = require(ReplicatedStorage.Shared.Clients.EffectClient)
local Manifest = require(ReplicatedStorage.Shared.Manifest)
local Timeline = require(ReplicatedStorage.Shared.Timeline)

local HEIGHT = 6

type Entry = {
	Model: Model,
	LastPosition: Vector3,
	StartPosition: Vector3,
	MiddlePosition: Vector3,
	EndPosition: Vector3,
}

return function(args: { Model: Model, Duration: number, Manifest: Manifest.Node })
	local nodeModel = args.Model
	local bonusFolder = nodeModel:FindFirstChild("Bonus") :: Folder
	local centerCFrame = nodeModel:GetPivot()
	local entries: { Entry } = {}

	return Manifest.Await(bonusFolder, args.Manifest):andThen(function()
		for _, child in bonusFolder:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local endPosition = child:GetPivot().Position
			local startPosition = centerCFrame.Position
			local delta = endPosition - startPosition

			table.insert(entries, {
				Model = child,
				LastPosition = startPosition - Vector3.new(0, 1, 0) + delta.Unit,
				StartPosition = startPosition,
				MiddlePosition = startPosition:Lerp(endPosition, 0.75) + Vector3.new(0, HEIGHT, 0),
				EndPosition = endPosition,
			})
		end

		return Timeline(args.Duration, function(alpha)
			for _, entry in entries do
				local ab = entry.StartPosition:Lerp(entry.MiddlePosition, alpha)
				local bc = entry.MiddlePosition:Lerp(entry.EndPosition, alpha)
				local p = ab:Lerp(bc, alpha)
				local delta = p - entry.LastPosition
				if delta:FuzzyEq(Vector3.zero) then
					delta = Vector3.xAxis
				end
				entry.LastPosition = p
				local cframe = CFrame.lookAlong(p, -delta) * CFrame.Angles(-math.pi / 2, 0, 0)
				entry.Model:PivotTo(cframe)
			end
		end):andThen(function()
			for _, entry in entries do
				EffectClient.Effect("EmitCount", {
					Path = "Base/Emitters/DustRing",
					Count = 16,
					Target = entry.EndPosition,
				})
			end
		end)
	end)
end
