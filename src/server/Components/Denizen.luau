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

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local Behavior = require(ServerScriptService.Server.Behavior.Behavior)
local AbilityServer = require(ServerScriptService.Server.Servers.AbilityServer)
local CombatServer = require(ServerScriptService.Server.Servers.CombatServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local DamageTypes = require(ReplicatedStorage.Shared.Types.DamageTypes)
local DenizenDefs = require(ReplicatedStorage.Shared.Defs.DenizenDefs)

type CombatSession = CombatTypes.CombatSession
type Damage = DamageTypes.Damage

type DenizenDef = DenizenDefs.DenizenDef

local ARRIVAL_THRESHOLD = 0.5
-- Distance below the RootPart's foot the GroundSensor will reach for. Generous so the
-- denizen doesn't lose ground contact on small slopes or step-downs.
local GROUND_SENSOR_BUFFER = 5
-- Out-of-combat regen rate, expressed as a fraction of MaxHealth per second. Denizens
-- only regenerate while CombatSession is nil; in-combat regen is intentionally zero.
local OUT_OF_COMBAT_REGEN_FRACTION = 0.25
-- Coin drop range awarded on death to each player who was in combat with the denizen.
-- Inclusive on both ends. Will move to the def when per-kind drops matter.
local COIN_DROP_MIN = 5
local COIN_DROP_MAX = 15

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

	self.MoveTarget = nil :: Vector3?
	self.FacingTarget = nil :: Vector3?
	self.ControllerManager = nil :: ControllerManager?

	self.SpawnPosition = self.Instance:GetPivot().Position
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
	CombatServer.Disengage(self)
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
	Returns the denizen's pivot CFrame (position + facing). Implements the `Combatant`
	interface for combat-system range and direction checks.
	@within Denizen
	@return CFrame
]=]
function Denizen:GetCFrame(): CFrame
	return self.Instance:GetPivot()
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

	local target = self.MoveTarget
	if target ~= nil then
		local position = self.Instance:GetPivot().Position
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
	if self.Health <= 0 and not self.IsDead then
		self:Die()
	end
end

--[=[
	Kills the denizen: pays out coins to every player that was in a combat session with
	it, then destroys the model. The model's destruction triggers the component's `Stop`,
	which in turn `Disengage`s any remaining combat session reference.

	Idempotent — guarded by `IsDead` so a flurry of damage hits in one frame can't
	double-pay the loot.
	@within Denizen
]=]
function Denizen:Die()
	self.IsDead = true

	-- Snapshot rewarded players before disengaging — `Disengage` (run from `Stop`) ends
	-- the session and clears `Members`, so we'd see an empty list afterwards.
	local rewardedPlayers: { Player } = {}
	local session = self.CombatSession
	if session ~= nil then
		for member in session.Members do
			if member.Player ~= nil then
				table.insert(rewardedPlayers, member.Player)
			end
		end
	end

	for _, player in rewardedPlayers do
		local count = math.random(COIN_DROP_MIN, COIN_DROP_MAX)
		InventoryServer.AddItem(player, "Coin", count)
	end

	self.Instance:Destroy()
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
	forwarded to `AnimationTrack:Play` (e.g. `fadeTime`, `weight`, `speed`).
	@within Denizen
	@param kind string
]=]
function Denizen:AnimationPlay(kind: string, ...: any)
	getOrLoadTrack(self, kind):Play(...)
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
