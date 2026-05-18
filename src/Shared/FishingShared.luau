--!strict

--[=[
	@class FishingShared
	Pure constants and helpers for the fishing system that are needed on both
	server (mechanics) and client (UI). Frenzy timing in particular has to live
	here so the client can locally tick the on-screen countdown bar from a
	single `FrenzyExpiresAt` timestamp instead of the server replicating the
	meter every Heartbeat.
]=]

local FishingShared = {}

--[=[
	@prop FrenzyDuration number
	@within FishingShared
	Wall-clock seconds a fishing spot stays in `Frenzy` state before it
	auto-returns to `Normal`.
]=]
FishingShared.FrenzyDuration = 30

--[=[
	@prop FrenzyIntervalMultiplier number
	@within FishingShared
	Multiplier applied to the rod's `Interval` while the fishing spot is in
	`Frenzy` (0.5 → 2× faster ticks).
]=]
FishingShared.FrenzyIntervalMultiplier = 0.5

--[=[
	@prop FrenzyCatchMultiplier number
	@within FishingShared
	Multiplier applied to the player's effective catch chance while the fishing
	spot is in `Frenzy` (2× — capped at 1 by the consumer).
]=]
FishingShared.FrenzyCatchMultiplier = 2

return FishingShared
