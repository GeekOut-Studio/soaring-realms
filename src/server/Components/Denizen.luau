--!strict

--[=[
	@class Denizen
	Server component for non-player combat-capable inhabitants of the realm — neutral
	creatures, friendly NPCs, hostile mobs. Counterpart to `Outworlder` for entities that
	don't have a `Player`.

	Reads a `DenizenKind` attribute, looks up the matching `DenizenDef`, and:

	- Maintains authoritative health, exposing `GetHealth`/`SetHealth` so the instance
	  satisfies the `DamageTarget` interface for the central `DamageServer` pipeline.
	- Manages an animation track cache via the model's `AnimationController`/`Animator`.
	  No Humanoid — Denizens don't participate in the default Roblox character pipeline.
	- Plays the def's idle animation for the lifetime of the denizen.
	- Drives physics-based locomotion via a programmatically-constructed `ControllerManager`
	  (`GroundController` + `AirController` + a `ControllerPartSensor` for ground detection).
	  No Humanoid means no built-in MoveTo / state machine, so movement is reconciled into
	  `ControllerManager.MovingDirection` and `FacingDirection` from `MoveTarget` and
	  `FacingTarget` state every heartbeat.

	Reads one attribute:
	- `DenizenKind` (`DenizenKind`) — selects the def in `DenizenDefs`.

	Model contract:
	- The model must have a `PrimaryPart` set, and that part must be unanchored. The
	  PrimaryPart's assembly is handed to the server via `SetNetworkOwner(nil)`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local Behavior = require(ServerScriptService.Server.Behavior.Behavior)
local AbilityServer = require(ServerScriptService.Server.Servers.AbilityServer)
local CombatServer = require(ServerScriptService.Server.Servers.CombatServer)
local LootServer = require(ServerScriptService.Server.Servers.LootServer)
local AbilityTypes = require(ReplicatedStorage.Shared.Types.AbilityTypes)
local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local DamageTypes = require(ReplicatedStorage.Shared.Types.DamageTypes)
local DenizenDefs = require(ReplicatedStorage.Shared.Defs.DenizenDefs)
local LootShared = require(ReplicatedStorage.Shared.LootShared)
local LootTypes = require(ReplicatedStorage.Shared.Types.LootTypes)

type CombatSession = CombatTypes.CombatSession
type Damage = DamageTypes.Damage
type PlayerLoot = LootTypes.PlayerLoot

type DenizenDef = DenizenDefs.DenizenDef

local ARRIVAL_THRESHOLD = 0.5
-- Distance below the RootPart's foot the GroundSensor will reach for. Generous so the
-- denizen doesn't lose ground contact on small slopes or step-downs.
local GROUND_SENSOR_BUFFER = 5
-- Out-of-combat regen rate, expressed as a fraction of MaxHealth per second. Denizens
-- only regenerate while CombatSession is nil; in-combat regen is intentionally zero.
local OUT_OF_COMBAT_REGEN_FRACTION = 0.25

local Denizen = Component.new({
	Tag = "Denizen",
	Ancestors = { Workspace },
})

--[=[
	@prop Def DenizenDef
	@within Denizen
]=]

--[=[
	@prop MaxHealth number
	@within Denizen
	Snapshot of `Def.MaxHealth`. Will become dynamic when level/buff systems land.
]=]

--[=[
	@prop Health number
	@within Denizen
	Authoritative current health (0..MaxHealth). Mutated through `SetHealth` from the
	damage pipeline.
]=]

--[=[
	@prop AnimationTracks {[string]: AnimationTrack}
	@within Denizen
	Cache of `AnimationTrack`s lazily loaded by `AnimationPlay`. Keyed by the animation
	name from `AnimationDefs`.
]=]

--[=[
	@prop ControllerManager ControllerManager
	@within Denizen
	The physics movement controller, constructed in `Start`. Mutating `MovingDirection`
	and `FacingDirection` is the way to drive the denizen.
]=]

--[=[
	@prop MoveTarget Vector3?
	@within Denizen
	When non-nil, `HeartbeatUpdate` steers the denizen toward this point each frame and
	clears the field automatically once the denizen arrives.
]=]

--[=[
	@prop FacingTarget Vector3?
	@within Denizen
	When non-nil, `HeartbeatUpdate` writes this direction into `FacingDirection` each
	frame. When nil, the denizen faces along its current movement.
]=]

--[=[
	@prop SpawnPosition Vector3
	@within Denizen
	The denizen's PrimaryPart position at construction. Behavior states use this as the
	anchor for wander/leash/return-to-spawn logic.
]=]

--[=[
	@prop LastDamagedTime number?
	@within Denizen
	`os.clock()` of the most recent `OnDidTakeDamage` call. `nil` until the first hit. Read
	by the `RecentlyDamaged` / `NotRecentlyDamaged` predicates.
]=]

--[=[
	@prop LastAttacker DamageSource?
	@within Denizen
	The `Source` of the most recent damage event. `nil` for environmental damage or until
	first hit. Read by `Flee` to pick a flee direction.
]=]

--[=[
	@prop Target any?
	@within Denizen
	The current behavior target — typically an `Outworlder` stashed by the `EnemyInRange`
	predicate and consumed by `MeleeAggression` / `Flee`.
]=]

--[=[
	@prop Behavior any?
	@within Denizen
	The per-denizen FSM runner, present iff the def has a `Behavior` field. Ticked once per
	heartbeat before movement reconciliation.
]=]

--[=[
	@prop CombatSession CombatSession?
	@within Denizen
	Back-reference written by `CombatServer`. Non-nil exactly when the denizen is in
	combat. Read by behavior states and the `InCombat` predicate.
]=]

--[=[
	@prop Comm any
	@within Denizen
	Per-instance `Comm.ServerComm`. Exposes `MaxHealth`, `Health`, and `InCombat` so
	clients (e.g. `DenizenClient`) can render an overhead health bar without each
	denizen needing its own ad-hoc remote setup.
]=]

function Denizen:Construct()
	local kind = self.Instance:GetAttribute("DenizenKind")
	local name = self.Instance:GetFullName()
	assert(t.keyOf(DenizenDefs)(kind), `{name}: bad DenizenKind attribute`)

	local primary = self.Instance.PrimaryPart
	assert(primary ~= nil, `{name}: Denizen model must have a PrimaryPart`)
	assert(not primary.Anchored, `{name}: Denizen PrimaryPart must be unanchored`)

	self.Def = DenizenDefs[kind] :: DenizenDef
	self.Trove = Trove.new()
	self.AnimationTracks = {} :: { [string]: AnimationTrack }
	self.Animator = nil :: Animator?

	self.MaxHealth = self.Def.MaxHealth
	self.Health = self.MaxHealth

	self.Comm = Comm.ServerComm.new(self.Instance, "Denizen")
	self.Trove:Add(self.Comm)
	self.MaxHealthProperty = self.Comm:CreateProperty("MaxHealth", self.MaxHealth)
	self.HealthProperty = self.Comm:CreateProperty("Health", self.Health)
	self.InCombatProperty = self.Comm:CreateProperty("InCombat", false)

	self.MoveTarget = nil :: Vector3?
	self.FacingTarget = nil :: Vector3?
	self.ControllerManager = nil :: ControllerManager?

	self.SpawnPosition = primary.Position
	self.LastDamagedTime = nil :: number?
	self.LastAttacker = nil :: any?
	self.Target = nil :: any?
	self.Behavior = nil :: any?
	self.CombatSession = nil :: CombatSession?
	self.IsDead = false

	self:SetUpController()

	if self.Def.Behavior ~= nil then
		self.Behavior = Behavior.new(self, self.Def.Behavior)
	end
end

function Denizen:Start()
	local idle = self.Def.Animations.Idle
	if idle ~= nil then
		self:AnimationPlay(idle)
	end
	self.Trove:Add(CombatServer.RegisterCombatant(self))
end

--[=[
	Constructs the `ControllerManager` rig (controllers + ground sensor) and parents it
	under the model. Hands physics ownership of the assembly to the server. Everything
	created here is added to `self.Trove` so it's torn down when the component stops.
	@within Denizen
	@private
]=]
function Denizen:SetUpController()
	local primary = self.Instance.PrimaryPart :: BasePart
	primary:SetNetworkOwner(nil)

	local manager = Instance.new("ControllerManager")
	manager.Name = "ControllerManager"
	manager.RootPart = primary
	manager.BaseMoveSpeed = self.Def.MoveSpeed

	local groundController = Instance.new("GroundController")
	groundController.Parent = manager

	local airController = Instance.new("AirController")
	airController.Parent = manager

	local groundSensor = Instance.new("ControllerPartSensor")
	groundSensor.Name = "GroundSensor"
	groundSensor.SensorMode = Enum.SensorMode.Floor
	groundSensor.SearchDistance = primary.Size.Y / 2 + GROUND_SENSOR_BUFFER
	groundSensor.Parent = primary
	self.Trove:Add(groundSensor)

	manager.ActiveController = groundController
	manager.GroundSensor = groundSensor
	manager.Parent = self.Instance
	self.Trove:Add(manager)

	self.ControllerManager = manager
end

function Denizen:Stop()
	AbilityServer.ResetCooldowns(self)
	self:AnimationStopHardAll()
	self.Trove:Destroy()
end

--[=[
	Returns the team identifier for this denizen, sourced from the def. `nil` means the
	denizen is hostile to everyone. Implements the `Combatant` interface.
	@within Denizen
	@return string?
]=]
function Denizen:GetTeam(): string?
	return self.Def.Team
end

--[=[
	Returns the denizen's `PrimaryPart` CFrame (position + facing). Implements
	the `Combatant` interface. Anchored to `PrimaryPart` rather than the model
	pivot so cross-rig spatial queries stay consistent — a Denizen model's
	pivot is often at its feet, while its `PrimaryPart` (asserted at
	`Construct`) sits at the assembly's intended center.
	@within Denizen
	@return CFrame
]=]
function Denizen:GetCFrame(): CFrame
	return (self.Instance.PrimaryPart :: BasePart).CFrame
end

--[=[
	Returns the denizen's root `BasePart` (its `PrimaryPart`). Satisfies the
	`AbilityActivator.GetRoot` contract.
	@within Denizen
	@return BasePart
]=]
function Denizen:GetRoot(): BasePart
	return self.Instance.PrimaryPart :: BasePart
end

--[=[
	Sets a destination point. The denizen will steer toward it on every heartbeat until
	it arrives (within `ARRIVAL_THRESHOLD`) or `StopMoving` is called.
	@within Denizen
	@param point Vector3
]=]
function Denizen:MoveTo(point: Vector3)
	self.MoveTarget = point
end

--[=[
	Sets an explicit facing direction. While set, the denizen faces this direction
	regardless of movement. Pass `nil` to fall back to facing along movement.
	@within Denizen
	@param direction Vector3?
]=]
function Denizen:FaceDirection(direction: Vector3?)
	self.FacingTarget = direction
end

--[=[
	Pivots the denizen to face `target` on the horizontal plane via the
	`ControllerManager` (no Humanoid in the way, unlike `Outworlder:FaceTowards`).
	`target` is resolved via `AbilityTypes.ResolveFaceTarget` (see that module
	for accepted input shapes). Vertical component is discarded so the body stays upright.
	No-ops when the flat delta is approximately zero. `duration` is accepted for `AbilityActivator`
	interface parity with `Outworlder:FaceTowards` but currently ignored — the
	denizen's behavior states already drive `FacingTarget` over time, so a
	timed-hold variant isn't needed yet.
	@within Denizen
	@param target AbilityTypes.FaceTarget
	@param _duration number?
]=]
function Denizen:FaceTowards(target: AbilityTypes.FaceTarget, _duration: number?)
	local point = AbilityTypes.ResolveFaceTarget(target)
	local currentPosition = self:GetCFrame().Position
	local delta = (point - currentPosition) * Vector3.new(1, 0, 1)
	if delta:FuzzyEq(Vector3.zero) then
		return
	end
	self:FaceDirection(delta.Unit)
end

--[=[
	Stops the denizen from walking toward its `MoveTarget`. Does not change facing.
	@within Denizen
]=]
function Denizen:StopMoving()
	self.MoveTarget = nil
end

function Denizen:HeartbeatUpdate(dt: number)
	local manager = self.ControllerManager
	if manager == nil then
		return
	end

	if self.Behavior ~= nil then
		self.Behavior:Tick(dt)
	end

	if self.CombatSession == nil and self.Health > 0 and self.Health < self.MaxHealth then
		self:SetHealth(self.Health + self.MaxHealth * OUT_OF_COMBAT_REGEN_FRACTION * dt)
	end

	local inCombat = self.CombatSession ~= nil
	if inCombat ~= self.InCombatProperty:Get() then
		self.InCombatProperty:Set(inCombat)
	end

	local target = self.MoveTarget
	if target ~= nil then
		local position = self:GetCFrame().Position
		local dx = target.X - position.X
		local dz = target.Z - position.Z
		if dx * dx + dz * dz < ARRIVAL_THRESHOLD * ARRIVAL_THRESHOLD then
			self.MoveTarget = nil
			manager.MovingDirection = Vector3.zero
		else
			manager.MovingDirection = Vector3.new(dx, 0, dz).Unit
		end
	else
		manager.MovingDirection = Vector3.zero
	end

	local moving = not manager.MovingDirection:FuzzyEq(Vector3.zero)

	local facing = self.FacingTarget
	if facing ~= nil then
		manager.FacingDirection = facing
	elseif moving then
		manager.FacingDirection = manager.MovingDirection
	end

	local run = self.Def.Animations.Run
	if run ~= nil then
		if moving and not self:AnimationIsPlaying(run) then
			self:AnimationPlay(run)
		elseif not moving and self:AnimationIsPlaying(run) then
			self:AnimationStop(run)
		end
	end
end

--[=[
	Implements `DamageTarget`. Returns the denizen's current health.
	@within Denizen
	@return number
]=]
function Denizen:GetHealth(): number
	return self.Health
end

--[=[
	Implements `DamageTarget`. Sets authoritative health, clamped to `[0, MaxHealth]`.
	Triggers `Die` once on the transition to zero; subsequent calls at zero are no-ops.
	@within Denizen
	@param value number
]=]
function Denizen:SetHealth(value: number)
	self.Health = math.clamp(value, 0, self.MaxHealth)
	self.HealthProperty:Set(self.Health)
	if self.Health <= 0 then
		self:Die()
	end
end

--[=[
	Kills the denizen: rolls the def's `LootTable` once per eligible player (every
	player in our combat session at time of death), registers the resulting per-
	player loot map with `LootServer` keyed by our model, then hands the model off
	to the `DenizenCorpse` component (via tag swap) so the def's death animation,
	if any, can play past our own lifecycle. `DenizenCorpse` resolves the pending
	drop when the body finishes despawning, materializing a `LootBag` at the
	corpse's location.

	Removing the `Denizen` tag triggers our `Stop` — which tears down
	`ControllerManager`, behavior, `Comm`, and the combat registration. The
	`AnimationController`/`Animator` are children of the model proper (not owned
	by our `Trove`), so they survive into the corpse phase.

	Idempotent — guarded by `IsDead` so a flurry of damage hits in one frame can't
	double-roll the loot.
	@within Denizen
]=]
function Denizen:Die()
	if self.IsDead then
		return
	end
	self.IsDead = true

	-- Roll loot before disengaging — `Disengage` (run from `Stop`) clears the
	-- session's `Members`, so we'd see an empty eligibility list afterwards.
	local lootTable = self.Def.LootTable
	local session = self.CombatSession
	if lootTable ~= nil and session ~= nil then
		local playerLoot: { [Player]: PlayerLoot } = {}
		for member in session.Members do
			local player = member.Player
			if player == nil then
				continue
			end
			local roll = LootShared.RollLootTable(lootTable)
			if #roll > 0 then
				playerLoot[player] = roll
			end
		end
		if next(playerLoot) ~= nil then
			LootServer.RegisterPendingDrop(self.Instance, playerLoot)
		end
	end

	-- Hard-stop our active tracks before handing off so the death animation plays
	-- cleanly. Our own `Stop` would also call this, but the relative ordering of
	-- Stop vs. the corpse component's Construct under the Component package's
	-- `task.defer` isn't guaranteed.
	self:AnimationStopHardAll()

	self.Instance:RemoveTag("Denizen")
	self.Instance:AddTag("DenizenCorpse")
end

--[=[
	Implements `DamageTarget`'s post-apply hook: stamps `LastDamagedTime` and remembers the
	`Source` as `LastAttacker` so the behavior layer can react. Returns the unchanged
	`Damage` record (we don't transform here).
	@within Denizen
	@param damage Damage
	@return Damage
]=]
function Denizen:OnDidTakeDamage(damage: Damage): Damage
	self.LastDamagedTime = os.clock()
	self.LastAttacker = damage.Source
	return damage
end

--[=[
	Returns the denizen's `Animator`, lazily resolving it from the `AnimationController`
	on first access and caching the result.
	@within Denizen
	@return Animator
]=]
function Denizen:GetAnimator(): Animator
	if self.Animator ~= nil then
		return self.Animator
	end
	local controller = self.Instance:FindFirstChildOfClass("AnimationController") :: AnimationController?
	assert(controller ~= nil, `Denizen: {self.Instance:GetFullName()} has no AnimationController`)
	local animator = controller:FindFirstChildOfClass("Animator") :: Animator?
	assert(animator ~= nil, `Denizen: {self.Instance:GetFullName()} has no Animator under AnimationController`)
	self.Animator = animator
	return animator
end

local function getOrLoadTrack(self, kind: string): AnimationTrack
	local track = self.AnimationTracks[kind]
	if track ~= nil then
		return track
	end
	local animation = AnimationDefs[kind]
	track = self:GetAnimator():LoadAnimation(animation)
	self.AnimationTracks[kind] = track
	return track
end

--[=[
	Plays the animation identified by `kind`, loading it on first use. Extra arguments are
	forwarded to `AnimationTrack:Play` (e.g. `fadeTime`, `weight`, `speed`). Returns the
	underlying `AnimationTrack` so callers can read e.g. `Length` for timing decisions.
	@within Denizen
	@param kind string
	@return AnimationTrack
]=]
function Denizen:AnimationPlay(kind: string, ...: any): AnimationTrack
	local track = getOrLoadTrack(self, kind)
	track:Play(...)
	return track
end

--[=[
	Stops the animation identified by `kind`. Returns silently if the track was never
	loaded. Extra arguments are forwarded to `AnimationTrack:Stop`.
	@within Denizen
	@param kind string
]=]
function Denizen:AnimationStop(kind: string, ...: any)
	local track = self.AnimationTracks[kind]
	if track == nil then
		return
	end
	track:Stop(...)
end

--[=[
	Stops the animation identified by `kind` immediately by zeroing its weight before
	stopping with no fade. Returns silently if the track was never loaded.
	@within Denizen
	@param kind string
]=]
function Denizen:AnimationStopHard(kind: string)
	local track = self.AnimationTracks[kind]
	if track == nil then
		return
	end
	track:AdjustWeight(0, 0)
	track:Stop(0)
end

--[=[
	Hard-stops every cached animation track. Used to forcibly clear all animation state.
	@within Denizen
]=]
function Denizen:AnimationStopHardAll()
	for _, track in self.AnimationTracks do
		track:AdjustWeight(0, 0)
		track:Stop(0)
	end
end

--[=[
	Returns whether the track for `kind` is currently loaded and playing.
	@within Denizen
	@param kind string
	@return boolean
]=]
function Denizen:AnimationIsPlaying(kind: string): boolean
	local track = self.AnimationTracks[kind]
	return track ~= nil and track.IsPlaying
end

return Denizen
