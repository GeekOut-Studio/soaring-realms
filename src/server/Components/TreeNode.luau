--!strict

--[=[
	@class TreeNode
	Component placed on tree-node models in the world. Authoritatively manages
	the woodcutting lifecycle:

	- The stump always carries a proximity prompt that starts a looping woodcutting
	  action on the activating player's `Outworlder`. Stump hits grant 1× progress
	  and contribute to a shared cut meter.
	- Filling the cut meter advances the node to `Falling` state for a brief
	  `FALLING_DURATION` window: the `TreeFall1` sound plays from the stump and the
	  cut meter stops accumulating, but the stump prompt and any in-progress
	  choppers continue unaffected.
	- After the falling window the node transitions to `Bonus` state: the `Trunk`
	  part snaps to a fallen pose (its `BaseAttachment.WorldCFrame` aligned to
	  `Stump.FallenTrunkAttachment.WorldCFrame`), the `Top` part is unparented, and
	  the trunk's own prompt becomes active. Trunk hits grant 2× progress and do
	  not contribute to the cut meter.
	- After a fixed bonus duration the node enters `Depleted` (trunk unparented,
	  only stump remains and stays mineable). After a recharge duration the trunk
	  and top return to their original poses and the cycle restarts.

	The component expects the following children on `self.Instance`:
	- `Stump` (BasePart) with an attachment named `FallenTrunkAttachment` defining
	  where the trunk's base should rest in the fallen pose.
	- `Trunk` (BasePart) with an attachment named `BaseAttachment` defining the
	  point on the trunk that aligns with `FallenTrunkAttachment`.
	- `Top` (Instance) — anything; parent and pivot are cached for restoration.

	Reads one attribute:
	- `TreeNodeKind` (`TreeNodeKind`) — selects the def in `TreeNodeDefs`.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local EffectServer = require(ServerScriptService.Server.Servers.EffectServer)
local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local RequirementsServer = require(ServerScriptService.Server.Servers.RequirementsServer)
local SkillServer = require(ServerScriptService.Server.Servers.SkillServer)
local Outworlder = require(ServerScriptService.Server.Components.Outworlder)
local ActionPrompts = require(ReplicatedStorage.Shared.ActionPrompts)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)
local TreeNodeDefs = require(ReplicatedStorage.Shared.Defs.TreeNodeDefs)
local SkillShared = require(ReplicatedStorage.Shared.SkillShared)
local WeightedRandom = require(ReplicatedStorage.Shared.WeightedRandom)

type Action = ActionTypes.Action
type StopReason = ActionTypes.StopReason
type TreeNodeDef = TreeNodeDefs.TreeNodeDef
type Drops = TreeNodeDefs.Drops
type WoodcuttingStats = ItemStatsTypes.WoodcuttingStats

local BONUS_DURATION = 45
local RECHARGE_DURATION = 60
local FALLING_DURATION = 2.2
local PROMPT_DISTANCE = 7

--[=[
	@type State "Normal" | "Falling" | "Bonus" | "Depleted"
	@within TreeNode
]=]
type State = "Normal" | "Falling" | "Bonus" | "Depleted"

--[=[
	@interface NodeEntry
	@within TreeNode
	@field Key string -- Stable identifier sent to the client. `"Stump"` or `"Trunk"`.
	@field Root BasePart -- The part holding the proximity prompt and used for distance checks.
	@field Prompt ProximityPrompt
	@field PlayerProgress {[Player]: number} -- Per-player progress meter, 0..1.
	@field EfficiencyMultiplier number -- Progress-rate multiplier (stump 1, trunk 2).
	@field ContributesToCut boolean -- Whether hits also fill the shared cut meter (stump only).
]=]
type NodeEntry = {
	Key: string,
	Root: BasePart,
	Prompt: ProximityPrompt,
	PlayerProgress: { [Player]: number },
	EfficiencyMultiplier: number,
	ContributesToCut: boolean,
}

type ActiveCutter = {
	Outworlder: any,
	Action: Action,
	Entry: NodeEntry,
	CurrentAnimation: string,
}

-- The stump in Normal state is a standing trunk — players swing horizontally
-- to cut through it. Once the trunk falls (Bonus) or has fallen and been
-- consumed (Depleted, stump-only), the cut surface is roughly waist-height and
-- horizontal, so an overhead swing fits. The fallen trunk is similarly chopped
-- overhead.
local function getAnimationFor(entry: NodeEntry, state: State): string
	if entry.Key == "Stump" and state == "Normal" then
		return "ToolHorizontalSwing"
	end
	return "ToolOverheadSwing"
end

local TreeNode = Component.new({
	Tag = "TreeNode",
	Ancestors = { Workspace },
})

--[=[
	@prop Def TreeNodeDef
	@within TreeNode
]=]

--[=[
	@prop State State
	@within TreeNode
]=]

--[=[
	@prop CutProgress number
	@within TreeNode
	0..1. Only ticks while `State == "Normal"`.
]=]

local function makePrompt(actionText: string, objectText: string, parent: Instance): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:AddTag(ActionPrompts.Tag)
	-- Default wanting-on; callers override for initially-hidden entries (e.g.
	-- the trunk prompt while in Normal). See `ActionPrompts` for the
	-- layered-gate contract.
	ActionPrompts.SetServerEnabled(prompt, true)
	prompt.Parent = parent
	return prompt
end

local function pickDrop(drops: Drops): string
	if typeof(drops) == "string" then
		return drops
	end
	return WeightedRandom.Pick(drops).Kind
end

local function isInRange(outworlder: any, entry: NodeEntry): boolean
	local position = outworlder:GetCFrame().Position
	return (position - entry.Root.Position).Magnitude <= PROMPT_DISTANCE
end

local function findWoodcuttingStats(player: Player): WoodcuttingStats?
	local equipment = EquipmentServer.GetEquipment(player)
	local item = equipment.MainHandMelee
	if item == nil then
		return nil
	end
	local def = ItemDefs[item.Kind]
	if def == nil or def.Stats == nil then
		return nil
	end
	return def.Stats.Woodcutting
end

function TreeNode:Construct()
	local kind = self.Instance:GetAttribute("TreeNodeKind")
	local name = self.Instance:GetFullName()
	assert(t.keyOf(TreeNodeDefs)(kind), `{name}: bad TreeNodeKind attribute`)

	self.Def = TreeNodeDefs[kind] :: TreeNodeDef
	self.Trove = Trove.new()
	self.State = "Normal" :: State
	self.CutProgress = 0
	self.ActiveCutters = {} :: { [Player]: ActiveCutter }
	self.StateThread = nil :: thread?
	self.Random = Random.new()

	self.Comm = Comm.ServerComm.new(self.Instance, "TreeNode")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:CreateProperty("State", self.State)
	self.CutProperty = self.Comm:CreateProperty("Cut", self.CutProgress)
	self.HitSignal = self.Comm:CreateSignal("Hit")

	local stumpChild = self.Instance:FindFirstChild("Stump")
	local trunkChild = self.Instance:FindFirstChild("Trunk")
	local topChild = self.Instance:FindFirstChild("Top")
	assert(stumpChild ~= nil and stumpChild:IsA("BasePart"), `{name}: missing child BasePart "Stump"`)
	assert(trunkChild ~= nil and trunkChild:IsA("BasePart"), `{name}: missing child BasePart "Trunk"`)
	assert(topChild ~= nil, `{name}: missing child "Top"`)
	local stump = stumpChild :: BasePart
	local trunk = trunkChild :: BasePart

	local fallenAttachment = stump:FindFirstChild("FallenTrunkAttachment")
	local baseAttachment = trunk:FindFirstChild("BaseAttachment")
	assert(
		fallenAttachment ~= nil and fallenAttachment:IsA("Attachment"),
		`{name}: Stump missing Attachment "FallenTrunkAttachment"`
	)
	assert(
		baseAttachment ~= nil and baseAttachment:IsA("Attachment"),
		`{name}: Trunk missing Attachment "BaseAttachment"`
	)

	self.Stump = stump
	self.Trunk = trunk
	self.Top = topChild
	self.FallenAttachment = fallenAttachment :: Attachment
	self.BaseAttachment = baseAttachment :: Attachment

	self.TrunkOriginalCFrame = trunk.CFrame

	local stumpPrompt = makePrompt("Chop", self.Def.Name, stump)
	local stumpEntry: NodeEntry = {
		Key = "Stump",
		Root = stump,
		Prompt = stumpPrompt,
		PlayerProgress = {},
		EfficiencyMultiplier = 1,
		ContributesToCut = true,
	}
	self.StumpEntry = stumpEntry
	self.Trove:Connect(stumpPrompt.Triggered, function(player: Player)
		self:HandlePromptTriggered(player, stumpEntry)
	end)

	local trunkPrompt = makePrompt("Chop", self.Def.Name, trunk)
	ActionPrompts.SetServerEnabled(trunkPrompt, false)
	local trunkEntry: NodeEntry = {
		Key = "Trunk",
		Root = trunk,
		Prompt = trunkPrompt,
		PlayerProgress = {},
		EfficiencyMultiplier = 2,
		ContributesToCut = false,
	}
	self.TrunkEntry = trunkEntry
	self.Trove:Connect(trunkPrompt.Triggered, function(player: Player)
		self:HandlePromptTriggered(player, trunkEntry)
	end)

	self.Trove:Connect(Players.PlayerRemoving, function(player: Player)
		self:OnPlayerRemoving(player)
	end)
end

--[=[
	Drops references to a leaving player so their progress entries don't pin the
	`Player` instance for the lifetime of the node.
	@within TreeNode
	@param player Player
]=]
function TreeNode:OnPlayerRemoving(player: Player)
	self:StopCutterAction(player)
	self.StumpEntry.PlayerProgress[player] = nil
	self.TrunkEntry.PlayerProgress[player] = nil
end

function TreeNode:Stop()
	self:CancelStateThread()
	for player in self.ActiveCutters do
		self:StopCutterAction(player)
	end
	self.Trove:Destroy()
end

--[=[
	Cancels the state-transition timer (bonus or recharge) if one is running.
	@within TreeNode
]=]
function TreeNode:CancelStateThread()
	if self.StateThread ~= nil then
		task.cancel(self.StateThread)
		self.StateThread = nil
	end
end

--[=[
	Stops `player`'s active woodcutting action on this node, if any. The action's
	`Stop` callback clears the `ActiveCutters` entry, so we route through
	`Outworlder:StopCurrentAction` whenever it still owns our action.
	@within TreeNode
	@param player Player
]=]
function TreeNode:StopCutterAction(player: Player)
	local cutter = self.ActiveCutters[player]
	if cutter == nil then
		return
	end
	if cutter.Outworlder.CurrentAction == cutter.Action then
		cutter.Outworlder:StopCurrentAction("Interrupted")
	else
		self.ActiveCutters[player] = nil
	end
end

--[=[
	Routes a proximity-prompt activation into a new woodcutting action on the
	player's `Outworlder`. Requirements gating happens in `BeginCutting` so it
	isn't duplicated against the per-swing recheck.
	@within TreeNode
	@param player Player
	@param entry NodeEntry
]=]
function TreeNode:HandlePromptTriggered(player: Player, entry: NodeEntry)
	local character = player.Character
	if character == nil then
		return
	end
	local outworlder = Outworlder:FromInstance(character)
	if outworlder == nil then
		return
	end
	self:BeginCutting(player, outworlder, entry)
end

--[=[
	Gates entry to the woodcutting action on `self.Def.Requirements` and on the
	player being within `PROMPT_DISTANCE` of the entry's root, then constructs the
	looping action for `player` on the given entry and hands it to their
	`Outworlder`. Requirements and proximity are re-checked at the top of every
	swing tick; any failure ends the action with `Result.Fail` and a notification.

	The axe's `WoodcuttingStats` are re-read every Update tick so a mid-action
	tool swap is reflected immediately in both damage and swing cadence.
	@within TreeNode
	@param player Player
	@param outworlder any -- The player's `Outworlder` component.
	@param entry NodeEntry
]=]
function TreeNode:BeginCutting(player: Player, outworlder: any, entry: NodeEntry)
	local node = self
	local def = self.Def

	local ok, message = RequirementsServer.CheckForPlayer(player, def.Requirements)
	if not ok then
		outworlder:NotifyActionFailed(message or "You can't do that right now.")
		return
	end
	if not isInRange(outworlder, entry) then
		outworlder:NotifyActionFailed("You're too far away.")
		return
	end
	-- The HasEquipmentWithStats("MainHandMelee", "Woodcutting") requirement above
	-- guarantees this lookup succeeds; the assertion is defensive against drift.
	local stats = findWoodcuttingStats(player)
	assert(stats ~= nil, "woodcutting requirement passed but no woodcutting stats found")

	local initialInterval = stats.Interval
	local elapsed = 0

	outworlder:StartAction({
		Name = "Woodcutting",
		AllowsMovement = false,
		CompletionTimestamp = Workspace:GetServerTimeNow() + initialInterval,
		Alpha = nil,
		Start = function(actionSelf)
			local initialAnimation = getAnimationFor(entry, node.State)
			node.ActiveCutters[player] = {
				Outworlder = outworlder,
				Action = actionSelf,
				Entry = entry,
				CurrentAnimation = initialAnimation,
			}
			outworlder:FaceTowards(entry.Root.Position)
			outworlder:AnimationPlayWithDuration(initialAnimation, initialInterval)
		end,
		Update = function(actionSelf, dt)
			elapsed += dt
			local currentStats = findWoodcuttingStats(player)
			if currentStats == nil then
				outworlder:NotifyActionFailed("You can't do that right now.")
				return ActionTypes.Result.Fail
			end
			local interval = currentStats.Interval
			while elapsed >= interval do
				elapsed -= interval
				local stillOk, stillMessage = RequirementsServer.CheckForPlayer(player, def.Requirements)
				if not stillOk then
					outworlder:NotifyActionFailed(stillMessage or "You can't do that right now.")
					return ActionTypes.Result.Fail
				end
				if not isInRange(outworlder, entry) then
					outworlder:NotifyActionFailed("You're too far away.")
					return ActionTypes.Result.Fail
				end
				node:OnHit(player, entry, currentStats)
				actionSelf.CompletionTimestamp = Workspace:GetServerTimeNow() + interval
				local cutter = node.ActiveCutters[player]
				local desiredAnimation = getAnimationFor(entry, node.State)
				if cutter ~= nil and cutter.CurrentAnimation ~= desiredAnimation then
					outworlder:AnimationStop(cutter.CurrentAnimation, 0.1)
					cutter.CurrentAnimation = desiredAnimation
				end
				outworlder:AnimationPlayWithDuration(desiredAnimation, interval)
			end
			return ActionTypes.Result.Continue
		end,
		Stop = function(_self, _reason: StopReason)
			local cutter = node.ActiveCutters[player]
			if cutter ~= nil then
				outworlder:AnimationStop(cutter.CurrentAnimation, 0.1)
			end
			node.ActiveCutters[player] = nil
		end,
	})
end

--[=[
	Applies the consequences of a single axe swing. The caller passes in the
	current `WoodcuttingStats`, scaled by the player's Woodcutting level via
	`SkillShared.Woodcutting.GetEffectivePower`; one value is rolled from the
	resulting range and used as damage against both the per-player progress meter
	(scaled by `EfficiencyMultiplier`) and, when the entry contributes, the
	shared cut meter. Grants drop+XP on a progress fill.
	@within TreeNode
	@param player Player
	@param entry NodeEntry
	@param stats WoodcuttingStats -- The axe stats in effect for this swing.
]=]
function TreeNode:OnHit(player: Player, entry: NodeEntry, stats: WoodcuttingStats)
	local cutter = self.ActiveCutters[player]
	assert(cutter ~= nil, "OnHit called for player with no active cutter")
	local def = self.Def

	EffectServer.EffectAll("PlaySound", {
		Target = entry.Root,
		Kind = `AxeHit{self.Random:NextInteger(1, 3)}`,
	})
	local woodcuttingLevel = SkillServer.GetSkills(player).Woodcutting.Level
	local minPower, maxPower = SkillShared.Woodcutting.GetEffectivePower(stats, woodcuttingLevel)
	local rolled = self.Random:NextNumber(minPower, maxPower)
	local progressIncrement = rolled * entry.EfficiencyMultiplier / def.ProgressHealth

	local newProgress = (entry.PlayerProgress[player] or 0) + progressIncrement
	while newProgress >= 1 do
		newProgress -= 1
		self:GrantProgressFill(player)
	end
	entry.PlayerProgress[player] = newProgress
	self.HitSignal:Fire(player, { Root = entry.Root, EntryKey = entry.Key, Progress = newProgress })

	if entry.ContributesToCut and self.State == "Normal" then
		self.CutProgress += rolled / def.CutHealth
		if self.CutProgress >= 1 then
			self.CutProgress = 0
			self:EnterFalling()
		end
		self.CutProperty:Set(self.CutProgress)
	end
end

--[=[
	Transitions to `Falling` state. Plays the tree-fall sound from the stump and
	schedules the visual `Bonus` transition `FALLING_DURATION` seconds later. The
	`OnHit` cut-meter gate (`self.State == "Normal"`) naturally stops the meter
	from accumulating during this window; the stump prompt and any in-progress
	choppers are untouched and continue to swing.
	@within TreeNode
]=]
function TreeNode:EnterFalling()
	self.State = "Falling"
	self.StateProperty:Set(self.State)

	EffectServer.EffectAll("PlaySound", {
		Target = self.Stump,
		Kind = "TreeFall1",
	})
	EffectServer.EffectAll("TreeNodeFall", {
		Model = self.Instance,
		Duration = FALLING_DURATION,
	})

	self:CancelStateThread()
	self.StateThread = task.delay(FALLING_DURATION, function()
		self.StateThread = nil
		self:EnterBonus()
	end)
end

--[=[
	Awards XP and a drop to `player` for filling a per-player progress meter once.
	@within TreeNode
	@param player Player
]=]
function TreeNode:GrantProgressFill(player: Player)
	local kind = pickDrop(self.Def.Drops)
	InventoryServer.AddItem(player, kind, 1)
	SkillServer.AddExperience(player, "Woodcutting", self.Def.ExperiencePerProgress)
end

--[=[
	Transitions to `Bonus` state. The shared cut meter is reset, the trunk snaps
	to its fallen pose (aligned by attachment), the top is unparented, and the
	trunk's prompt becomes active. Per spec, this does NOT interrupt players
	currently cutting the stump.
	@within TreeNode
]=]
function TreeNode:EnterBonus()
	self.State = "Bonus"
	self.StateProperty:Set(self.State)
	self.CutProperty:Set(self.CutProgress)

	-- Place the trunk so its BaseAttachment world CFrame equals the stump's
	-- FallenTrunkAttachment world CFrame: trunk.CFrame * baseAttachment.CFrame =
	-- fallenAttachment.WorldCFrame ⇒ trunk.CFrame = fallenAttachment.WorldCFrame *
	-- baseAttachment.CFrame:Inverse().
	self.Trunk.CFrame = self.FallenAttachment.WorldCFrame * self.BaseAttachment.CFrame:Inverse()
	self.Top.Parent = nil

	self.TrunkEntry.PlayerProgress = {}
	ActionPrompts.SetServerEnabled(self.TrunkEntry.Prompt, true)

	self:CancelStateThread()
	self.StateThread = task.delay(BONUS_DURATION, function()
		self.StateThread = nil
		self:EnterDepleted()
	end)
end

--[=[
	Transitions to `Depleted` state. The trunk is unparented and any in-progress
	cutting on it is interrupted. The stump remains cuttable for normal progress.
	After the recharge timer, returns to `Normal`.
	@within TreeNode
]=]
function TreeNode:EnterDepleted()
	self.State = "Depleted"
	self.StateProperty:Set(self.State)
	ActionPrompts.SetServerEnabled(self.TrunkEntry.Prompt, false)
	self.Trunk.Parent = nil
	for player, cutter in self.ActiveCutters do
		if cutter.Entry == self.TrunkEntry then
			self:StopCutterAction(player)
		end
	end
	self:CancelStateThread()
	self.StateThread = task.delay(RECHARGE_DURATION, function()
		self.StateThread = nil
		self:EnterNormal()
	end)
end

--[=[
	Transitions back to `Normal` state. The trunk and top are restored to their
	original parents and CFrames, and the cut meter starts accumulating again on
	subsequent stump hits.
	@within TreeNode
]=]
function TreeNode:EnterNormal()
	self.State = "Normal"
	self.StateProperty:Set(self.State)
	self.CutProgress = 0
	self.CutProperty:Set(self.CutProgress)

	self.Trunk.CFrame = self.TrunkOriginalCFrame
	self.Trunk.Parent = self.Instance
	self.Top.Parent = self.Instance
end

return TreeNode
