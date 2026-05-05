--!strict

--[=[
	@class OreNode
	Component placed on ore-node models in the world. Authoritatively manages the
	mining lifecycle:

	- A central proximity prompt starts a looping mining action on the activating
	  player's `Outworlder`.
	- Each entry (center + each bonus) carries an efficiency multiplier and a flag
	  for whether its hits also contribute to the shared break meter. Center hits
	  contribute and grant 1× progress; bonus hits do not contribute and grant 2×.
	- Each entry has a per-player progress meter that fills with that player's hits;
	  on fill, the player receives an experience grant and a drop.
	- Filling the break meter advances the node to `Bonus` state, surfacing the
	  bonus child entries. After a fixed bonus duration the node enters `Depleted`,
	  then after a recharge duration returns to `Normal`.

	The component expects a child structure of `Normal`, `Depleted`, and `Bonus`
	(folder of `Bonus` models) on `self.Instance`. Only the currently active center
	visual is parented to the model; the other one and the bonus models are kept in
	`nil` with strong references so they survive garbage collection.

	The proximity prompts live on programmatically-created invisible root parts so
	the visual models themselves stay purely decorative.

	Reads one attribute:
	- `OreNodeKind` (`OreNodeKind`) — selects the def in `OreNodeDefs`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local SkillServer = require(ServerScriptService.Server.Servers.SkillServer)
local Outworlder = require(ServerScriptService.Server.Components.Outworlder)
local ActionTypes = require(ReplicatedStorage.Shared.Types.ActionTypes)
local OreNodeDefs = require(ReplicatedStorage.Shared.Defs.OreNodeDefs)
local WeightedRandom = require(ReplicatedStorage.Shared.WeightedRandom)

type Action = ActionTypes.Action
type StopReason = ActionTypes.StopReason
type OreNodeDef = OreNodeDefs.OreNodeDef
type Drops = OreNodeDefs.Drops

local SWING_INTERVAL = 1
local BONUS_DURATION = 15
local RECHARGE_DURATION = 60
local PROMPT_DISTANCE = 10

--[=[
	@type State "Normal" | "Bonus" | "Depleted"
	@within OreNode
]=]
type State = "Normal" | "Bonus" | "Depleted"

--[=[
	@interface NodeEntry
	@within OreNode
	@field Key string -- Stable identifier sent to the client. `"Center"` or `"Bonus<i>"` (1-based).
	@field Root BasePart -- Invisible part holding the proximity prompt.
	@field Prompt ProximityPrompt
	@field Model Model? -- The visual whose `Parent` we toggle. `nil` for the center entry, which always exists.
	@field PlayerProgress {[Player]: number} -- Per-player progress meter, 0..1.
	@field EfficiencyMultiplier number -- Progress-rate multiplier (center 1, bonuses 2).
	@field ContributesToBreak boolean -- Whether hits also fill the shared break meter (center only).
]=]
type NodeEntry = {
	Key: string,
	Root: BasePart,
	Prompt: ProximityPrompt,
	Model: Model?,
	PlayerProgress: { [Player]: number },
	EfficiencyMultiplier: number,
	ContributesToBreak: boolean,
}

type ActiveMiner = {
	Outworlder: any,
	Action: Action,
	Entry: NodeEntry,
}

local OreNode = Component.new({
	Tag = "OreNode",
	Ancestors = { Workspace },
})

--[=[
	@prop Def OreNodeDef
	@within OreNode
]=]

--[=[
	@prop State State
	@within OreNode
]=]

--[=[
	@prop BreakProgress number
	@within OreNode
	0..1. Only ticks while `State == "Normal"`.
]=]

local function makeRootPart(name: string, cframe: CFrame, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function makePrompt(actionText: string, objectText: string, parent: Instance): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function pickDrop(drops: Drops): string
	if typeof(drops) == "string" then
		return drops
	end
	return WeightedRandom.Pick(drops).Kind
end

function OreNode:Construct()
	local kind = self.Instance:GetAttribute("OreNodeKind")
	local name = self.Instance:GetFullName()
	assert(t.keyOf(OreNodeDefs)(kind), `{name}: bad OreNodeKind attribute`)

	self.Def = OreNodeDefs[kind] :: OreNodeDef
	self.Trove = Trove.new()
	self.State = "Normal" :: State
	self.BreakProgress = 0
	self.ActiveMiners = {} :: { [Player]: ActiveMiner }
	self.StateThread = nil :: thread?

	self.Comm = Comm.ServerComm.new(self.Instance, "OreNode")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:CreateProperty("State", self.State)
	self.BreakProperty = self.Comm:CreateProperty("Break", self.BreakProgress)
	self.HitSignal = self.Comm:CreateSignal("Hit")

	local normalChild = self.Instance:FindFirstChild("Normal")
	local depletedChild = self.Instance:FindFirstChild("Depleted")
	local bonusChild = self.Instance:FindFirstChild("Bonus")
	assert(normalChild ~= nil and normalChild:IsA("Model"), `{name}: missing child Model "Normal"`)
	assert(depletedChild ~= nil and depletedChild:IsA("Model"), `{name}: missing child Model "Depleted"`)
	assert(bonusChild ~= nil and bonusChild:IsA("Folder"), `{name}: missing child Folder "Bonus"`)
	local normalModel = normalChild :: Model
	local depletedModel = depletedChild :: Model
	local bonusFolder = bonusChild :: Folder

	self.NormalModel = normalModel
	self.DepletedModel = depletedModel
	self.BonusFolder = bonusFolder

	depletedModel.Parent = nil
	self.Trove:Add(depletedModel)

	local centerRoot = makeRootPart("Root", self.Instance:GetPivot(), self.Instance)
	self.Trove:Add(centerRoot)
	local centerPrompt = makePrompt("Mine", self.Def.Name, centerRoot)
	local centerEntry: NodeEntry = {
		Key = "Center",
		Root = centerRoot,
		Prompt = centerPrompt,
		Model = nil,
		PlayerProgress = {},
		EfficiencyMultiplier = 1,
		ContributesToBreak = true,
	}
	self.CenterEntry = centerEntry
	self.Trove:Connect(centerPrompt.Triggered, function(player: Player)
		self:HandlePromptTriggered(player, centerEntry)
	end)

	self.BonusEntries = {} :: { NodeEntry }
	for index, child in bonusFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local pivot = child:GetPivot()
		child.Parent = nil
		self.Trove:Add(child)

		local root = makeRootPart("Root", pivot, child)
		local prompt = makePrompt("Mine", self.Def.Name, root)
		prompt.Enabled = false
		local entry: NodeEntry = {
			Key = `Bonus{index}`,
			Root = root,
			Prompt = prompt,
			Model = child,
			PlayerProgress = {},
			EfficiencyMultiplier = 2,
			ContributesToBreak = false,
		}
		self.Trove:Connect(prompt.Triggered, function(player: Player)
			self:HandlePromptTriggered(player, entry)
		end)
		table.insert(self.BonusEntries, entry)
	end
end

function OreNode:Stop()
	self:CancelStateThread()
	for player in self.ActiveMiners do
		self:StopMinerAction(player)
	end
	self.Trove:Destroy()
end

--[=[
	Cancels the state-transition timer (bonus or recharge) if one is running.
	@within OreNode
]=]
function OreNode:CancelStateThread()
	if self.StateThread ~= nil then
		task.cancel(self.StateThread)
		self.StateThread = nil
	end
end

--[=[
	Stops `player`'s active mining action on this node, if any. The action's `Stop`
	callback clears the `ActiveMiners` entry, so we route through
	`Outworlder:StopCurrentAction` whenever it still owns our action.
	@within OreNode
	@param player Player
]=]
function OreNode:StopMinerAction(player: Player)
	local miner = self.ActiveMiners[player]
	if miner == nil then
		return
	end
	if miner.Outworlder.CurrentAction == miner.Action then
		miner.Outworlder:StopCurrentAction("Interrupted")
	else
		self.ActiveMiners[player] = nil
	end
end

--[=[
	Routes a proximity-prompt activation into a new mining action on the player's
	`Outworlder`.
	@within OreNode
	@param player Player
	@param entry NodeEntry
]=]
function OreNode:HandlePromptTriggered(player: Player, entry: NodeEntry)
	local character = player.Character
	if character == nil then
		return
	end
	local outworlder = Outworlder:FromInstance(character)
	if outworlder == nil then
		return
	end
	self:BeginMining(player, outworlder, entry)
end

--[=[
	Constructs the looping mining `Action` for `player` on the given entry and
	hands it to their `Outworlder`. Movement-based interruption is handled by
	`Outworlder` (it consults `Action.AllowsMovement`).
	@within OreNode
	@param player Player
	@param outworlder any -- The player's `Outworlder` component.
	@param entry NodeEntry
]=]
function OreNode:BeginMining(player: Player, outworlder: any, entry: NodeEntry)
	local node = self
	local elapsed = 0

	local action: Action = {
		Name = "Mining",
		AllowsMovement = false,
		CompletionTimestamp = Workspace:GetServerTimeNow() + SWING_INTERVAL,
		Alpha = nil,
		Update = function(actionSelf, dt)
			elapsed += dt
			while elapsed >= SWING_INTERVAL do
				elapsed -= SWING_INTERVAL
				node:OnHit(player, entry)
				actionSelf.CompletionTimestamp = Workspace:GetServerTimeNow() + SWING_INTERVAL
			end
			return ActionTypes.Result.Continue
		end,
		Stop = function(_self, _reason: StopReason)
			node.ActiveMiners[player] = nil
		end,
	}

	self.ActiveMiners[player] = {
		Outworlder = outworlder,
		Action = action,
		Entry = entry,
	}
	outworlder:FaceTowards(entry.Root.Position)
	outworlder:StartAction(action)
end

--[=[
	Applies the consequences of a single pickaxe swing: increments the entry's
	progress meter (scaled by `EfficiencyMultiplier`), grants drop+XP on a fill,
	and ticks the shared break meter when the entry contributes to it.
	@within OreNode
	@param player Player
	@param entry NodeEntry
]=]
function OreNode:OnHit(player: Player, entry: NodeEntry)
	local def = self.Def
	local progressIncrement = SWING_INTERVAL / def.ProgressDifficulty * entry.EfficiencyMultiplier

	local newProgress = (entry.PlayerProgress[player] or 0) + progressIncrement
	while newProgress >= 1 do
		newProgress -= 1
		self:GrantProgressFill(player)
	end
	entry.PlayerProgress[player] = newProgress
	self.HitSignal:Fire(player, { Root = entry.Root, EntryKey = entry.Key, Progress = newProgress })

	if entry.ContributesToBreak and self.State == "Normal" then
		self.BreakProgress += SWING_INTERVAL / def.BreakDifficulty
		if self.BreakProgress >= 1 then
			self.BreakProgress = 0
			self:EnterBonus()
		end
		self.BreakProperty:Set(self.BreakProgress)
	end
end

--[=[
	Awards XP and a drop to `player` for filling a per-player progress meter once.
	@within OreNode
	@param player Player
]=]
function OreNode:GrantProgressFill(player: Player)
	local kind = pickDrop(self.Def.Drops)
	InventoryServer.AddItem(player, kind, 1):catch(function(err)
		warn(`OreNode drop AddItem failed: {err}`)
	end)
	SkillServer.AddExperience(player, "Mining", self.Def.ExperiencePerProgress):catch(function(err)
		warn(`OreNode XP AddExperience failed: {err}`)
	end)
end

--[=[
	Swaps the visible center model. The depleted visual replaces the normal one
	whenever the node is in `Bonus` or `Depleted` state.
	@within OreNode
	@param wantDepleted boolean
]=]
function OreNode:ApplyCenterVisual(wantDepleted: boolean)
	if wantDepleted then
		self.NormalModel.Parent = nil
		self.DepletedModel.Parent = self.Instance
	else
		self.DepletedModel.Parent = nil
		self.NormalModel.Parent = self.Instance
	end
end

--[=[
	Transitions to `Bonus` state. The shared break meter is reset, the center
	visual swaps to the depleted model, and bonus entries are surfaced. Per spec,
	this does NOT interrupt players currently mining the center node.
	@within OreNode
]=]
function OreNode:EnterBonus()
	self.State = "Bonus"
	self.StateProperty:Set(self.State)
	self.BreakProperty:Set(self.BreakProgress)
	self:ApplyCenterVisual(true)
	for _, entry in self.BonusEntries do
		entry.PlayerProgress = {}
		assert(entry.Model ~= nil, "bonus entry missing model")
		entry.Model.Parent = self.Instance
		entry.Prompt.Enabled = true
	end
	self:CancelStateThread()
	self.StateThread = task.delay(BONUS_DURATION, function()
		self.StateThread = nil
		self:EnterDepleted()
	end)
end

--[=[
	Transitions to `Depleted` state. Bonus entries are removed from the world and
	any in-progress mining on them is interrupted. The center entry remains
	mineable for normal progress. After the recharge timer, returns to `Normal`.
	@within OreNode
]=]
function OreNode:EnterDepleted()
	self.State = "Depleted"
	self.StateProperty:Set(self.State)
	for _, entry in self.BonusEntries do
		entry.Prompt.Enabled = false
		assert(entry.Model ~= nil, "bonus entry missing model")
		entry.Model.Parent = nil
	end
	for player, miner in self.ActiveMiners do
		if miner.Entry ~= self.CenterEntry then
			self:StopMinerAction(player)
		end
	end
	self:CancelStateThread()
	self.StateThread = task.delay(RECHARGE_DURATION, function()
		self.StateThread = nil
		self:EnterNormal()
	end)
end

--[=[
	Transitions back to `Normal` state. The center visual restores to the normal
	model and the break meter starts accumulating again on subsequent center hits.
	@within OreNode
]=]
function OreNode:EnterNormal()
	self.State = "Normal"
	self.StateProperty:Set(self.State)
	self.BreakProgress = 0
	self.BreakProperty:Set(self.BreakProgress)
	self:ApplyCenterVisual(false)
end

return OreNode
