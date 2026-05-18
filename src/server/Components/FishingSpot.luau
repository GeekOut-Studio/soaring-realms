--!strict

--[=[
	@class FishingSpot
	Component placed on fishing-spot models in the world. Authoritatively manages
	the fishing lifecycle for a single spot and coordinates frenzy migration with
	its siblings under the same parent Folder (ad-hoc network — no group
	component).

	- A proximity prompt on the model's `InteractionPoint` part starts a looping
	  fishing action on the activating player's `Outworlder`. The action plays
	  `FishingCast` once on start and loops `FishingIdle` for the duration. The
	  player faces toward the model's `Root` part (not `InteractionPoint`).
	- Each action tick is one catch roll. On success: grant XP + a drop and play
	  `FishingCatch` as an overlay. On failure: keep idling.
	- While no spot in the parent group is in `Frenzy` state, each action tick on
	  a spot also adds one unit to that spot's frenzy bar (regardless of catch
	  outcome). On fill, a different random sibling is selected to enter
	  `Frenzy`; every sibling's bar is reset to 0.
	- The frenzied spot scales its tick interval (2× faster) and its catch
	  chance (2×) using multipliers from `FishingShared`. After the shared
	  frenzy duration the spot returns to `Normal`.

	The component expects two children on `self.Instance`:
	- `InteractionPoint` (BasePart) — hosts the proximity prompt and is the
	  range-check anchor. In Studio it's kept visible (with a `Line`
	  `RopeConstraint` running between `InteractionPoint.InteractionStart` and
	  `Root.InteractionEnd`) so designers can lay out spots intuitively; this
	  component hides the part and removes the line at startup.
	- `Root` (BasePart) — facing target and billboard anchor. Optionally hosts
	  a `Splashes` `ParticleEmitter` toggled on while the spot is `Frenzy`.

	Reads one attribute:
	- `FishingSpotKind` (`FishingSpotKind`) — selects the def.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local RequirementsServer = require(ServerScriptService.Server.Servers.RequirementsServer)
local SkillServer = require(ServerScriptService.Server.Servers.SkillServer)
local Outworlder = require(ServerScriptService.Server.Components.Outworlder)
local ActionPrompts = require(ReplicatedStorage.Shared.ActionPrompts)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local FishingShared = require(ReplicatedStorage.Shared.FishingShared)
local FishingSpotDefs = require(ReplicatedStorage.Shared.Defs.FishingSpotDefs)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)
local Parts = require(ReplicatedStorage.Shared.Parts)
local SkillShared = require(ReplicatedStorage.Shared.SkillShared)
local WeightedRandom = require(ReplicatedStorage.Shared.WeightedRandom)

type Action = ActionTypes.Action
type StopReason = ActionTypes.StopReason
type FishingSpotDef = FishingSpotDefs.FishingSpotDef
type Drops = FishingSpotDefs.Drops
type FishingStats = ItemStatsTypes.FishingStats

local PROMPT_DISTANCE = 7
local ACTIVE_PULSE_INTERVAL = 1

--[=[
	@type State "Normal" | "Frenzy" | "Suppressed"
	@within FishingSpot
	`Suppressed` means a *different* spot in the group is currently in `Frenzy`,
	so this spot's frenzy bar is locked at 0 and the build-up UI is hidden.
]=]
export type State = "Normal" | "Frenzy" | "Suppressed"

type ActiveFisher = {
	Outworlder: any,
	Action: Action,
}

--[=[
	@interface ActiveFisherEntry
	@within FishingSpot
	@field Player Player
	@field LocalAnchor Vector3 -- Offset from `Root.CFrame` for this player's water-side rope endpoint. Rolled server-side so every client renders the same point.
]=]
export type ActiveFisherEntry = {
	Player: Player,
	LocalAnchor: Vector3,
}

local FishingSpot = Component.new({
	Tag = "FishingSpot",
	Ancestors = { Workspace },
})

--[=[
	@prop Def FishingSpotDef
	@within FishingSpot
]=]

--[=[
	@prop State State
	@within FishingSpot
]=]

--[=[
	@prop FrenzyProgress number
	@within FishingSpot
	0..1. Only ticks while no spot in the parent group is in `Frenzy`.
]=]

local function pickDrop(drops: Drops): string
	if typeof(drops) == "string" then
		return drops
	end
	return WeightedRandom.Pick(drops).Kind
end

local function findFishingStats(player: Player): FishingStats?
	local equipment = EquipmentServer.GetEquipment(player)
	local item = equipment.MainHandMelee
	if item == nil then
		return nil
	end
	local def = ItemDefs[item.Kind]
	if def == nil or def.Stats == nil then
		return nil
	end
	return def.Stats.Fishing
end

function FishingSpot:Construct()
	local kind = self.Instance:GetAttribute("FishingSpotKind")
	local name = self.Instance:GetFullName()
	assert(t.keyOf(FishingSpotDefs)(kind), `{name}: bad FishingSpotKind attribute`)

	self.Def = FishingSpotDefs[kind] :: FishingSpotDef
	self.Trove = Trove.new()
	self.State = "Normal" :: State
	self.FrenzyProgress = 0
	self.ActiveFishers = {} :: { [Player]: ActiveFisher }
	self.FrenzyThread = nil :: thread?
	self.Random = Random.new()

	local interactionChild = self.Instance:FindFirstChild("InteractionPoint")
	local rootChild = self.Instance:FindFirstChild("Root")
	assert(
		interactionChild ~= nil and interactionChild:IsA("BasePart"),
		`{name}: missing child BasePart "InteractionPoint"`
	)
	assert(rootChild ~= nil and rootChild:IsA("BasePart"), `{name}: missing child BasePart "Root"`)
	self.InteractionPoint = interactionChild :: BasePart
	self.Root = rootChild :: BasePart

	Parts.MakeIntangible(self.InteractionPoint)

	local splashes = self.Root:FindFirstChild("Splashes")
	if splashes ~= nil and splashes:IsA("ParticleEmitter") then
		self.SplashesEmitter = splashes :: ParticleEmitter
		self.SplashesEmitter.Enabled = false
	end

	local line = self.InteractionPoint:FindFirstChild("Line")
	if line ~= nil then
		line.Attachment0:Destroy()
		line.Attachment1:Destroy()
		line:Destroy()
	end

	self.Comm = Comm.ServerComm.new(self.Instance, "FishingSpot")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:CreateProperty("State", self.State)
	self.FrenzyProperty = self.Comm:CreateProperty("Frenzy", self.FrenzyProgress)
	self.FrenzyExpiresAtProperty = self.Comm:CreateProperty("FrenzyExpiresAt", 0)
	self.ActiveSignal = self.Comm:CreateSignal("Active")
	-- Replicated list of currently fishing players, each paired with their
	-- per-session anchor offset (local to `Root`) for the water-side rope
	-- endpoint. The anchor is server-rolled so every client renders the same
	-- point on the water for a given player's session.
	self.ActiveFishersList = {} :: { ActiveFisherEntry }
	self.ActiveFishersProperty = self.Comm:CreateProperty("ActiveFishers", self.ActiveFishersList)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fish"
	prompt.ObjectText = self.Def.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:AddTag(ActionPrompts.Tag)
	ActionPrompts.SetServerEnabled(prompt, true)
	prompt.Parent = self.InteractionPoint
	self.Trove:Add(prompt)
	self.Prompt = prompt

	self.Trove:Connect(prompt.Triggered, function(player: Player)
		self:HandlePromptTriggered(player)
	end)

	self.Trove:Connect(Players.PlayerRemoving, function(player: Player)
		self:OnPlayerRemoving(player)
	end)
end

function FishingSpot:Start()
	-- Assertion deferred to Start so all sibling FishingSpot components have
	-- finished Construct before we count tags.
	local siblingCount = 0
	for _, child in self.Instance.Parent:GetChildren() do
		if child ~= self.Instance and child:HasTag("FishingSpot") then
			siblingCount += 1
		end
	end
	assert(
		siblingCount >= 1,
		`{self.Instance:GetFullName()}: needs at least one sibling FishingSpot (frenzy can never self-target)`
	)
end

function FishingSpot:Stop()
	if self.FrenzyThread ~= nil then
		task.cancel(self.FrenzyThread)
		self.FrenzyThread = nil
	end
	for player in self.ActiveFishers do
		self:StopFisherAction(player)
	end
	self.Trove:Destroy()
end

--[=[
	Drops the player's active fishing action on this spot when they leave.
	@within FishingSpot
	@param player Player
]=]
function FishingSpot:OnPlayerRemoving(player: Player)
	self:StopFisherAction(player)
end

--[=[
	Stops `player`'s active fishing action on this spot, if any.
	@within FishingSpot
	@param player Player
]=]
function FishingSpot:StopFisherAction(player: Player)
	local fisher = self.ActiveFishers[player]
	if fisher == nil then
		return
	end
	if fisher.Outworlder.CurrentAction == fisher.Action then
		fisher.Outworlder:StopCurrentAction("Interrupted")
	else
		self.ActiveFishers[player] = nil
	end
end

--[=[
	Returns the parent-folder sibling FishingSpot components (excluding self).
	@within FishingSpot
	@return {FishingSpot}
]=]
function FishingSpot:GetSiblingSpots(): { any }
	local siblings = {}
	for _, child in self.Instance.Parent:GetChildren() do
		if child == self.Instance then
			continue
		end
		if not child:HasTag("FishingSpot") then
			continue
		end
		local sibling = FishingSpot:FromInstance(child)
		if sibling ~= nil then
			table.insert(siblings, sibling)
		end
	end
	return siblings
end

--[=[
	Routes a proximity-prompt activation into a new fishing action on the
	player's `Outworlder`. Requirements gating happens in `BeginFishing`.
	@within FishingSpot
	@param player Player
]=]
function FishingSpot:HandlePromptTriggered(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local outworlder = Outworlder:FromInstance(character)
	if outworlder == nil then
		return
	end
	self:BeginFishing(player, outworlder)
end

--[=[
	Gates entry to the fishing action on `self.Def.Requirements` and on the
	player being within `PROMPT_DISTANCE` of the spot's `InteractionPoint`, then
	constructs the looping action on the player's `Outworlder`. Each tick
	re-checks requirements, range, and that the rod is still equipped; on any
	failure the action ends with `Result.Fail`. The current `State` of the spot
	is read every tick so a mid-action transition into/out of `Frenzy` takes
	effect on the next tick boundary.
	@within FishingSpot
	@param player Player
	@param outworlder any -- The player's `Outworlder` component.
]=]
function FishingSpot:BeginFishing(player: Player, outworlder: any)
	local spot = self
	local def = self.Def

	local ok, message = RequirementsServer.CheckForPlayer(player, def.Requirements)
	if not ok then
		outworlder:NotifyActionFailed(message or "You can't do that right now.")
		return
	end
	if not spot:IsInRange(outworlder) then
		outworlder:NotifyActionFailed("You're too far away.")
		return
	end
	-- The HasEquipmentWithStats("MainHandMelee", "Fishing") requirement above
	-- guarantees this lookup succeeds; the assertion is defensive against drift.
	local stats = findFishingStats(player)
	assert(stats ~= nil, "fishing requirement passed but no fishing stats found")

	local initialInterval = spot:GetEffectiveInterval(stats)
	local elapsed = 0
	local lastInterval = initialInterval
	-- Seed for immediate first Active pulse.
	local activePulseElapsed = ACTIVE_PULSE_INTERVAL

	outworlder:StartAction({
		Name = "Fishing",
		AllowsMovement = false,
		CompletionTimestamp = Workspace:GetServerTimeNow() + initialInterval,
		Alpha = nil,
		Start = function(actionSelf)
			spot.ActiveFishers[player] = {
				Outworlder = outworlder,
				Action = actionSelf,
			}
			spot:AddActiveFisher(player)
			outworlder:FaceTowards(spot.Root.Position)
			outworlder:AnimationPlay("FishingIdle")
			outworlder:AnimationPlay("FishingCast")
		end,
		Update = function(actionSelf, dt)
			elapsed += dt
			activePulseElapsed += dt
			while activePulseElapsed >= ACTIVE_PULSE_INTERVAL do
				activePulseElapsed -= ACTIVE_PULSE_INTERVAL
				spot.ActiveSignal:Fire(player)
			end
			local currentStats = findFishingStats(player)
			if currentStats == nil then
				outworlder:NotifyActionFailed("You can't do that right now.")
				return ActionTypes.Result.Fail
			end
			local interval = spot:GetEffectiveInterval(currentStats)
			if interval ~= lastInterval then
				actionSelf.CompletionTimestamp = Workspace:GetServerTimeNow() + math.max(0, interval - elapsed)
				lastInterval = interval
			end
			while elapsed >= interval do
				elapsed -= interval
				local stillOk, stillMessage = RequirementsServer.CheckForPlayer(player, def.Requirements)
				if not stillOk then
					outworlder:NotifyActionFailed(stillMessage or "You can't do that right now.")
					return ActionTypes.Result.Fail
				end
				if not spot:IsInRange(outworlder) then
					outworlder:NotifyActionFailed("You're too far away.")
					return ActionTypes.Result.Fail
				end
				spot:OnTick(player, currentStats)
				-- Re-read interval after the tick — the tick itself may have
				-- migrated frenzy and changed our effective cadence.
				interval = spot:GetEffectiveInterval(currentStats)
				lastInterval = interval
				actionSelf.CompletionTimestamp = Workspace:GetServerTimeNow() + interval
			end
			return ActionTypes.Result.Continue
		end,
		Stop = function(_self, _reason: StopReason)
			outworlder:AnimationStop("FishingIdle")
			outworlder:AnimationStop("FishingCast")
			outworlder:AnimationStop("FishingCatch")
			spot.ActiveFishers[player] = nil
			spot:RemoveActiveFisher(player)
		end,
	})
end

--[=[
	Adds `player` to the replicated `ActiveFishers` list with a freshly rolled
	water-anchor offset (local to `Root`). The y component is the part's top
	surface; x/z are uniformly random within the part's extents.
	@within FishingSpot
	@param player Player
]=]
function FishingSpot:AddActiveFisher(player: Player)
	local size = self.Root.Size
	local anchor = Vector3.new(
		self.Random:NextNumber(-size.X / 2, size.X / 2),
		size.Y / 2,
		self.Random:NextNumber(-size.Z / 2, size.Z / 2)
	)
	local newList = table.clone(self.ActiveFishersList)
	table.insert(newList, { Player = player, LocalAnchor = anchor })
	self.ActiveFishersList = newList
	self.ActiveFishersProperty:Set(newList)
end

--[=[
	Removes `player` from the replicated `ActiveFishers` list. No-op if the
	player isn't currently listed.
	@within FishingSpot
	@param player Player
]=]
function FishingSpot:RemoveActiveFisher(player: Player)
	local index: number? = nil
	for i, entry in self.ActiveFishersList do
		if entry.Player == player then
			index = i
			break
		end
	end
	if index == nil then
		return
	end
	local newList = table.clone(self.ActiveFishersList)
	table.remove(newList, index)
	self.ActiveFishersList = newList
	self.ActiveFishersProperty:Set(newList)
end

--[=[
	Range check against `InteractionPoint.Position`. The prompt is hosted on
	`InteractionPoint`, so that's the position the player approached.
	@within FishingSpot
	@param outworlder any
	@return boolean
]=]
function FishingSpot:IsInRange(outworlder: any): boolean
	local position = outworlder:GetCFrame().Position
	return (position - self.InteractionPoint.Position).Magnitude <= PROMPT_DISTANCE
end

--[=[
	Returns this spot's currently effective tick interval given the player's
	rod stats. Scaled by the frenzy interval multiplier while in `Frenzy`.
	@within FishingSpot
	@param stats FishingStats
	@return number
]=]
function FishingSpot:GetEffectiveInterval(stats: FishingStats): number
	if self.State == "Frenzy" then
		return stats.Interval * FishingShared.FrenzyIntervalMultiplier
	end
	return stats.Interval
end

--[=[
	Applies one fishing tick: rolls a catch (with skill+frenzy scaling) and, if
	no spot in the group is frenzied, advances this spot's frenzy bar.
	@within FishingSpot
	@param player Player
	@param stats FishingStats -- The rod stats in effect for this tick.
]=]
function FishingSpot:OnTick(player: Player, stats: FishingStats)
	local def = self.Def
	local fishingLevel = SkillServer.GetSkills(player).Fishing.Level
	local catchChance = SkillShared.Fishing.GetEffectiveCatchChance(stats, fishingLevel)
	if self.State == "Frenzy" then
		catchChance = math.min(catchChance * FishingShared.FrenzyCatchMultiplier, 1)
	end

	if self.Random:NextNumber() < catchChance then
		local kind = pickDrop(def.Drops)
		InventoryServer.AddItem(player, kind, 1)
		SkillServer.AddExperience(player, "Fishing", def.ExperiencePerCatch)
		local outworlder = self.ActiveFishers[player].Outworlder
		outworlder:AnimationPlay("FishingCatch")
	end

	if self.State == "Normal" then
		self.FrenzyProgress += 1 / def.FrenzyHealth
		if self.FrenzyProgress >= 1 then
			self:TriggerFrenzyMigration()
		else
			self.FrenzyProperty:Set(self.FrenzyProgress)
		end
	end
end

--[=[
	Picks a different random sibling to enter `Frenzy`, then zeros every spot's
	frenzy bar (self and siblings). A spot can never frenzy itself per spec.
	@within FishingSpot
]=]
function FishingSpot:TriggerFrenzyMigration()
	local siblings = self:GetSiblingSpots()
	-- Construct assertion guarantees ≥1 sibling; defensive guard kept for the
	-- case where someone removes the second model at runtime.
	if #siblings == 0 then
		self:ResetFrenzyBar()
		return
	end
	local chosen = siblings[self.Random:NextInteger(1, #siblings)]
	self:ResetFrenzyBar()
	for _, sibling in siblings do
		sibling:ResetFrenzyBar()
	end
	chosen:EnterFrenzy()
end

--[=[
	Clears this spot's frenzy bar. Safe to call on a frenzied spot — it only
	touches the meter, not the state.
	@within FishingSpot
]=]
function FishingSpot:ResetFrenzyBar()
	self.FrenzyProgress = 0
	self.FrenzyProperty:Set(self.FrenzyProgress)
end

--[=[
	Enters `Frenzy` state and schedules the auto-exit timer. While frenzied
	this spot ticks faster and rolls a higher catch chance per the multipliers
	in `FishingShared`.
	@within FishingSpot
]=]
function FishingSpot:EnterFrenzy()
	self.State = "Frenzy"
	-- Set the expiry timestamp before the state flips so clients can't briefly
	-- observe state="Frenzy" with a stale `FrenzyExpiresAt` if the two
	-- properties happen to replicate on separate Heartbeat batches.
	self.FrenzyExpiresAtProperty:Set(Workspace:GetServerTimeNow() + FishingShared.FrenzyDuration)
	self.StateProperty:Set(self.State)
	for _, sibling in self:GetSiblingSpots() do
		sibling:EnterSuppressed()
	end
	if self.SplashesEmitter ~= nil then
		self.SplashesEmitter.Enabled = true
	end
	if self.FrenzyThread ~= nil then
		task.cancel(self.FrenzyThread)
	end
	self.FrenzyThread = task.delay(FishingShared.FrenzyDuration, function()
		self.FrenzyThread = nil
		self:ExitFrenzy()
	end)
end

--[=[
	Pushes this spot into `Suppressed` so its build-up bar is hidden client-side
	for the duration of a sibling's `Frenzy`. Called by the frenzying sibling.
	@within FishingSpot
]=]
function FishingSpot:EnterSuppressed()
	self.State = "Suppressed"
	self.StateProperty:Set(self.State)
end

--[=[
	Pulls this spot out of `Suppressed`, back to `Normal`. Called by the
	previously-frenzied sibling at the end of its frenzy window.
	@within FishingSpot
]=]
function FishingSpot:ExitSuppressed()
	self.State = "Normal"
	self.StateProperty:Set(self.State)
end

--[=[
	Returns to `Normal` state at the end of the frenzy timer. Frenzy bars across
	the group will start accumulating again on subsequent fishing ticks.
	@within FishingSpot
]=]
function FishingSpot:ExitFrenzy()
	self.State = "Normal"
	self.StateProperty:Set(self.State)
	self.FrenzyExpiresAtProperty:Set(0)
	for _, sibling in self:GetSiblingSpots() do
		sibling:ExitSuppressed()
	end
	if self.SplashesEmitter ~= nil then
		self.SplashesEmitter.Enabled = false
	end
end

return FishingSpot
