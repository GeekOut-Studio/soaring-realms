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

	Reads one attribute:
	- `DenizenKind` (`DenizenKind`) — selects the def in `DenizenDefs`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local DenizenDefs = require(ReplicatedStorage.Shared.Defs.DenizenDefs)

type DenizenDef = DenizenDefs.DenizenDef

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

function Denizen:Construct()
	local kind = self.Instance:GetAttribute("DenizenKind")
	local name = self.Instance:GetFullName()
	assert(t.keyOf(DenizenDefs)(kind), `{name}: bad DenizenKind attribute`)

	self.Def = DenizenDefs[kind] :: DenizenDef
	self.Trove = Trove.new()
	self.AnimationTracks = {} :: { [string]: AnimationTrack }
	self.Animator = nil :: Animator?

	self.MaxHealth = self.Def.MaxHealth
	self.Health = self.MaxHealth
end

function Denizen:Start()
	local idle = self.Def.Animations.Idle
	if idle ~= nil then
		self:AnimationPlay(idle)
	end
end

function Denizen:Stop()
	self:AnimationStopHardAll()
	self.Trove:Destroy()
end

--[=[
	Implements `DamageTarget`. Returns the denizen's current health.
	@within Denizen
	@server
	@return number
]=]
function Denizen:GetHealth(): number
	return self.Health
end

--[=[
	Implements `DamageTarget`. Sets authoritative health, clamped to `[0, MaxHealth]`.
	@within Denizen
	@server
	@param value number
]=]
function Denizen:SetHealth(value: number)
	self.Health = math.clamp(value, 0, self.MaxHealth)
end

--[=[
	Returns the denizen's `Animator`, lazily resolving it from the `AnimationController`
	on first access and caching the result.
	@within Denizen
	@server
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
	@server
	@param kind string
]=]
function Denizen:AnimationPlay(kind: string, ...: any)
	getOrLoadTrack(self, kind):Play(...)
end

--[=[
	Stops the animation identified by `kind`. Returns silently if the track was never
	loaded. Extra arguments are forwarded to `AnimationTrack:Stop`.
	@within Denizen
	@server
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
	@server
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
	@server
	@param kind string
	@return boolean
]=]
function Denizen:AnimationIsPlaying(kind: string): boolean
	local track = self.AnimationTracks[kind]
	return track ~= nil and track.IsPlaying
end

return Denizen
