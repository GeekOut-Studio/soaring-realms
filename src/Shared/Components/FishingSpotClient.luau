--!strict

--[=[
	@class FishingSpotClient
	Client-side companion to the server `FishingSpot` component. Two concerns:

	1. **Billboard registration (local player only).** Subscribes to the
	   owner-filtered `Active` pulse and to the `State`, `Frenzy`, and
	   `FrenzyExpiresAt` properties. The frenzy bar is registered for the local
	   player only while they are (or recently were) actively fishing this
	   spot — same per-player visibility model as `OreNodeClient` /
	   `TreeNodeClient`. After `BAR_VISIBILITY_SECONDS` without a pulse, the
	   billboard auto-prunes.

	2. **Fishing-line rendering (every client).** Subscribes to the
	   `ActiveFishers` property and, for every currently fishing player,
	   builds two `Line` `RopeConstraint` clones off the player's equipped
	   rod: one from the rod's `Line.Attachment0` to the character's
	   `LeftHand.LeftGripAttachment`, and one from `Line.Attachment1` to a
	   transient `Attachment` placed at the server-rolled `LocalAnchor` on
	   the spot's `Root` top surface. The original `Line` on the rod is left
	   alone. Per-player setup is owned by a sub-Trove keyed on the player so
	   removals (and respawns, via `Observers.observeCharacter`) reset cleanly.
]=]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Observers = require(ReplicatedStorage.Packages.Observers)
local Promise = require(ReplicatedStorage.Packages.Promise)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Billboards = require(ReplicatedStorage.Shared.React.Billboards.Billboards)
local EffectClient = require(ReplicatedStorage.Shared.Clients.EffectClient)
local FishingSpotBillboard = require(ReplicatedStorage.Shared.React.Billboards.FishingSpotBillboard)
local GetEffectsFolder = require(ReplicatedStorage.Shared.GetEffectsFolder)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)
local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local Timeline = require(ReplicatedStorage.Shared.Timeline)

local e = React.createElement

local rng = Random.new()

local BAR_VISIBILITY_SECONDS = 5
local WAIT_FOR_CHILD_TIMEOUT = 10

--[=[
	@type State "Normal" | "Frenzy" | "Suppressed"
	@within FishingSpotClient
]=]
export type State = "Normal" | "Frenzy" | "Suppressed"

type ActiveFisherEntry = {
	Player: Player,
	LocalAnchor: Vector3,
}

local FishingSpotClient = Component.new({
	Tag = "FishingSpot",
	Ancestors = { Workspace },
})

function FishingSpotClient:Construct()
	self.Trove = Trove.new()
	self.BillboardKey = nil :: string?
	self.ExpireThread = nil :: thread?
	self.LineTroves = {} :: { [Player]: any }

	local root = self.Instance:WaitForChild("Root", WAIT_FOR_CHILD_TIMEOUT)
	assert(
		root ~= nil and root:IsA("BasePart"),
		`FishingSpotClient: {self.Instance:GetFullName()} missing BasePart "Root"`
	)
	self.Root = root :: BasePart

	self.Comm = Comm.ClientComm.new(self.Instance, false, "FishingSpot")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:GetProperty("State")
	self.FrenzyProperty = self.Comm:GetProperty("Frenzy")
	self.FrenzyExpiresAtProperty = self.Comm:GetProperty("FrenzyExpiresAt")
	self.ActiveFishersProperty = self.Comm:GetProperty("ActiveFishers")
	self.ActiveSignal = self.Comm:GetSignal("Active")

	self.ActiveSignal:Connect(function()
		self:HandleActivePulse()
	end)

	self.ActiveFishersProperty:Observe(function(list: { ActiveFisherEntry })
		self:ReconcileActiveFishers(list or {})
	end)
end

function FishingSpotClient:Stop()
	if self.ExpireThread ~= nil then
		task.cancel(self.ExpireThread)
		self.ExpireThread = nil
	end
	if self.BillboardKey ~= nil then
		Billboards.Remove(self.BillboardKey)
		self.BillboardKey = nil
	end
	for player, trove in self.LineTroves do
		trove:Destroy()
		self.LineTroves[player] = nil
	end
	self.Trove:Destroy()
end

--[=[
	Records / refreshes the local-player billboard registration in response to
	a server `Active` pulse. Registers on first arrival, resets the expire
	timer on every subsequent arrival.
	@within FishingSpotClient
]=]
function FishingSpotClient:HandleActivePulse()
	if self.BillboardKey == nil then
		self.BillboardKey = `FishingSpot:{HttpService:GenerateGUID(false)}`
		Billboards.Set(self.BillboardKey, {
			Adornee = self.Root,
			Native = {},
			Render = function()
				return e(FishingSpotBillboard, {
					Node = self,
				})
			end,
		})
	end

	if self.ExpireThread ~= nil then
		task.cancel(self.ExpireThread)
	end
	self.ExpireThread = task.delay(BAR_VISIBILITY_SECONDS, function()
		self.ExpireThread = nil
		self:ExpireBillboard()
	end)
end

--[=[
	Removes the billboard registration after the local player has gone
	`BAR_VISIBILITY_SECONDS` without a pulse from this spot.
	@within FishingSpotClient
]=]
function FishingSpotClient:ExpireBillboard()
	if self.BillboardKey == nil then
		return
	end
	Billboards.Remove(self.BillboardKey)
	self.BillboardKey = nil
end

--[=[
	Diffs the incoming `ActiveFishers` list against `LineTroves` and creates /
	destroys per-player rope setups accordingly.
	@within FishingSpotClient
	@param list {ActiveFisherEntry}
]=]
function FishingSpotClient:ReconcileActiveFishers(list: { ActiveFisherEntry })
	local seen: { [Player]: true } = {}
	for _, entry in list do
		seen[entry.Player] = true
		if self.LineTroves[entry.Player] == nil then
			self:BeginLineRender(entry.Player, entry.LocalAnchor)
		end
	end
	for player, trove in self.LineTroves do
		if not seen[player] then
			trove:Destroy()
			self.LineTroves[player] = nil
		end
	end
end

--[=[
	Spins up a sub-Trove that observes `player`'s character, resolves their
	rendered rod via `OutworlderClient`, builds the two rope clones, and tears
	everything down on respawn or removal.
	@within FishingSpotClient
	@param player Player
	@param localAnchor Vector3 -- Position (in `Root`'s local space) for the water-side endpoint.
]=]
function FishingSpotClient:BeginLineRender(player: Player, localAnchor: Vector3)
	local trove = Trove.new()
	self.LineTroves[player] = trove

	local spot = self
	trove:Add(Observers.observeCharacter(function(observedPlayer: Player, character: Model)
		if observedPlayer ~= player then
			return
		end
		local sessionTrove = Trove.new()
		sessionTrove:AddPromise(OutworlderClient:WaitForInstance(character):andThen(function(outworlderClient)
			spot:AttachLineForCharacter(sessionTrove, character, outworlderClient, localAnchor)
		end))
		return sessionTrove:WrapClean()
	end))
end

--[=[
	Resolves the rod, the character's left-hand attachment, and the spot's
	water-anchor attachment, then clones the rod's `Line` `RopeConstraint`
	twice. Bails silently if any prerequisite never arrives (missing rod,
	missing attachments, etc.) — the rope simply doesn't render.
	@within FishingSpotClient
	@param sessionTrove any -- Per-character Trove that owns the resulting instances.
	@param character Model
	@param outworlderClient any -- The character's `OutworlderClient` component.
	@param localAnchor Vector3 -- Position (in `Root`'s local space) for the water-side endpoint.
]=]
function FishingSpotClient:AttachLineForCharacter(
	sessionTrove: any,
	character: Model,
	outworlderClient: any,
	localAnchor: Vector3
)
	local function isRod(model: Model?): boolean
		if model == nil then
			return false
		end
		local line = model:FindFirstChild("Line")
		return line ~= nil and line:IsA("RopeConstraint")
	end

	local rod = outworlderClient:GetRenderedModel("MainHandMelee")
	if not isRod(rod) then
		-- Rod still downloading or wrong item rendered; retry on the next
		-- MainHandMelee render that actually has a `Line` child.
		local connection
		connection = outworlderClient.RenderedEquipmentChanged:Connect(function(slot: string, model: Model?)
			if slot ~= "MainHandMelee" or not isRod(model) then
				return
			end
			connection:Disconnect()
			self:AttachLineForCharacter(sessionTrove, character, outworlderClient, localAnchor)
		end)
		sessionTrove:Add(function()
			connection:Disconnect()
		end)
		return
	end

	local origLine = rod:FindFirstChild("Line") :: RopeConstraint
	local origAttachment0 = origLine.Attachment0
	local origAttachment1 = origLine.Attachment1
	if origAttachment0 == nil or origAttachment1 == nil then
		return
	end

	local leftHand = character:WaitForChild("LeftHand", WAIT_FOR_CHILD_TIMEOUT)
	if leftHand == nil or not leftHand:IsA("BasePart") then
		return
	end
	local leftGripAttachment = leftHand:WaitForChild("LeftGripAttachment", WAIT_FOR_CHILD_TIMEOUT)
	if leftGripAttachment == nil or not leftGripAttachment:IsA("Attachment") then
		return
	end

	local waterAttachment = Instance.new("Attachment")
	waterAttachment.Name = "FishingLineEnd"
	waterAttachment.Position = localAnchor
	waterAttachment.Parent = self.Root
	sessionTrove:Add(waterAttachment)
	local waterAttachmentWorldCFrame = waterAttachment.WorldCFrame

	local handLine = origLine:Clone()
	handLine.Name = "HandLine"
	handLine.Attachment0 = origAttachment0
	handLine.Attachment1 = leftGripAttachment
	handLine.Parent = character
	sessionTrove:Add(handLine)

	-- Detached tracker so the rope can't tug the character.
	local rodTipTracker = Instance.new("Attachment")
	rodTipTracker.Name = "FishingRodTipTracker"
	rodTipTracker.WorldCFrame = origAttachment1.WorldCFrame
	-- Rope must be parented to a BasePart for rope to render.
	rodTipTracker.Parent = workspace.Terrain
	sessionTrove:Add(rodTipTracker)
	sessionTrove:Connect(RunService.Heartbeat, function()
		rodTipTracker.WorldCFrame = origAttachment1.WorldCFrame
	end)

	local waterLine = origLine:Clone()
	waterLine.Name = "WaterLine"
	waterLine.Visible = false
	waterLine.Attachment0 = rodTipTracker
	waterLine.Attachment1 = waterAttachment
	waterLine.Parent = GetEffectsFolder()
	sessionTrove:Add(waterLine)

	local function setLineLength(alpha: number)
		if alpha == 0 then
			waterLine.Visible = false
		else
			waterLine.Visible = true
			waterAttachment.WorldCFrame = waterAttachmentWorldCFrame:Lerp(rodTipTracker.WorldCFrame, 1 - alpha)
		end
	end
	setLineLength(0)

	local function playLandSound()
		EffectClient.Effect("PlaySound", {
			Target = waterAttachment,
			Kind = `FishingRodLand{rng:NextInteger(1, 4)}`,
		})
	end

	sessionTrove:AddPromise(Promise.delay(0.6)
		:andThen(function()
			EffectClient.Effect("PlaySound", { Target = origAttachment1, Kind = "FishingRodCast1" })
			return Timeline(0.25, function(alpha)
				setLineLength(alpha)
			end)
		end)
		:andThen(playLandSound))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator ~= nil then
			local activeCatchPromise: any = nil

			sessionTrove:Connect(animator.AnimationPlayed, function(track: AnimationTrack)
				if track.Animation.AnimationId ~= AnimationDefs.FishingCatch.AnimationId then
					return
				end

				if activeCatchPromise ~= nil then
					activeCatchPromise:cancel()
				end

				local promise
				promise = sessionTrove:AddPromise(Timeline(0.5, function(alpha)
						setLineLength(1 - alpha)
					end)
					:andThen(function()
						return Promise.delay(0.75)
					end)
					:andThen(function()
						return Timeline(0.25, function(alpha)
							setLineLength(alpha)
						end)
					end)
					:andThen(playLandSound)
					:finally(function()
						setLineLength(1)
						-- Only clear the slot if a later catch hasn't claimed it.
						if activeCatchPromise == promise then
							activeCatchPromise = nil
						end
					end))
				activeCatchPromise = promise
			end)
		end
	end
end

return FishingSpotClient
