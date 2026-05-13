--!strict

--[=[
	@class DenizenCorpse
	Server component for the `DenizenCorpse` tag, added by `Denizen:Die`
	after the denizen's combat / behavior / `Comm` machinery has been torn
	down. Plays the def's optional `Animations.Death` track on the model's
	surviving `Animator` (a child of the model proper, not owned by
	`Denizen`'s `Trove`) and destroys the model when the track finishes — at
	which point `DenizenRespawner` sees `AncestryChanged → Parent == nil` and
	starts its respawn timer.

	Death animations are expected to be non-looping; the component listens
	for `AnimationTrack.Stopped` to know when to clean up. If the def has no
	`Death` animation (or the model has no `Animator`), the model is
	destroyed immediately.

	Reads one attribute, the same one Denizen reads:
	- `DenizenKind` (`DenizenKind`) — selects the def in `DenizenDefs`.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local t = require(ReplicatedStorage.Packages.t)

local AnimationDefs = require(ReplicatedStorage.Shared.Defs.AnimationDefs)
local DenizenDefs = require(ReplicatedStorage.Shared.Defs.DenizenDefs)

local DenizenCorpse = Component.new({
	Tag = "DenizenCorpse",
	Ancestors = { Workspace },
})

--[=[
	@prop Def DenizenDef
	@within DenizenCorpse
]=]

function DenizenCorpse:Construct()
	self.Trove = Trove.new()

	local kind = self.Instance:GetAttribute("DenizenKind")
	local name = self.Instance:GetFullName()
	assert(t.keyOf(DenizenDefs)(kind), `{name}: bad DenizenKind attribute on corpse`)

	self.Def = DenizenDefs[kind]
end

function DenizenCorpse:Start()
	-- Anchor the root before doing anything else: `Denizen:Stop` already
	-- destroyed the `ControllerManager`, so without anchoring the body sinks
	-- through the floor under gravity. Animations drive Motor6D joints
	-- relative to the anchored root, so child parts still move as expected.
	local primary = self.Instance.PrimaryPart
	if primary ~= nil then
		primary.Anchored = true
	end

	local death = self.Def.Animations.Death
	if death == nil then
		self.Instance:Destroy()
		return
	end

	local animator = self:GetAnimator()
	if animator == nil then
		warn(`DenizenCorpse: {self.Instance:GetFullName()} has no Animator; destroying without animation`)
		self.Instance:Destroy()
		return
	end

	local animation = AnimationDefs[death]
	local track = animator:LoadAnimation(animation)
	track.Looped = false
	self.Trove:Add(track)
	self.Trove:Add(track.Stopped:Connect(function()
		-- Removing the tag first triggers our Stop synchronously through the
		-- Component package, cleaning up the track + Stopped connection before
		-- the model goes away. `Destroy` would still cascade-clean the track,
		-- but going through the component tear-down keeps the lifecycle path
		-- consistent.
		CollectionService:RemoveTag(self.Instance, "DenizenCorpse")
		self.Instance:Destroy()
	end))
	track:Play()
end

function DenizenCorpse:Stop()
	self.Trove:Destroy()
end

--[=[
	Returns the model's `Animator` (a child of its `AnimationController`),
	or `nil` if either is missing. Same lookup as `Denizen:GetAnimator` but
	non-asserting: a malformed/partially-destroyed model on the corpse path
	should fall through to "destroy without animation" rather than crash.
	@within DenizenCorpse
	@return Animator?
]=]
function DenizenCorpse:GetAnimator(): Animator?
	local controller = self.Instance:FindFirstChildOfClass("AnimationController") :: AnimationController?
	if controller == nil then
		return nil
	end
	return controller:FindFirstChildOfClass("Animator") :: Animator?
end

return DenizenCorpse
