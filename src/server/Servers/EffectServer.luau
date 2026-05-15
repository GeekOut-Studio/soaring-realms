--[=[
	@class EffectServer
	Server-side dispatcher for cosmetic effects. Sends a named effect plus its `args` to one
	or more clients, where `EffectClient` looks the name up in `ReplicatedStorage.Shared.Effects`
	and runs the matching effect module. Effects are purely visual/audio — never put gameplay
	logic in an effect module.

	Two parallel APIs:
	- `Effect` / `EffectAll` / `EffectFor` / `EffectExcept` for a single named effect.
	- `Effects` / `EffectsAll` / `EffectsFor` / `EffectsExcept` for a batch of `{Name, Args}`
	  entries delivered atomically over one signal — use when you want several effects to
	  arrive together (e.g. a sound and a visual that share a timing budget).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)

local EffectServer = {}

local effectSignal
local effectsSignal

--[=[
	@interface EffectEntry
	@within EffectServer
	@field Name string
	@field Args any
]=]
export type EffectEntry = { Name: string, Args: any }

function EffectServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Effect")
	effectSignal = serverComm:CreateSignal("Effect")
	effectsSignal = serverComm:CreateSignal("Effects")
end

--[=[
	Plays `effectName` for `player`.
	@within EffectServer
	@param player Player
	@param effectName string
	@param args any
]=]
function EffectServer.Effect(player: Player, effectName: string, args: any)
	effectSignal:Fire(player, effectName, args)
end

--[=[
	Plays `effectName` for every connected player.
	@within EffectServer
	@param effectName string
	@param args any
]=]
function EffectServer.EffectAll(effectName: string, args: any)
	effectSignal:FireAll(effectName, args)
end

--[=[
	Plays `effectName` for each player in `players`.
	@within EffectServer
	@param players {Player}
	@param effectName string
	@param args any
]=]
function EffectServer.EffectFor(players: { Player }, effectName: string, args: any)
	effectSignal:FireFor(players, effectName, args)
end

--[=[
	Plays `effectName` for every connected player except `ignorePlayer`.
	@within EffectServer
	@param ignorePlayer Player
	@param effectName string
	@param args any
]=]
function EffectServer.EffectExcept(ignorePlayer: Player, effectName: string, args: any)
	effectSignal:FireExcept(ignorePlayer, effectName, args)
end

--[=[
	Plays each effect in `batch` for `player` in a single packet.
	@within EffectServer
	@param player Player
	@param batch {EffectEntry}
]=]
function EffectServer.Effects(player: Player, batch: { EffectEntry })
	effectsSignal:Fire(player, batch)
end

--[=[
	Plays each effect in `batch` for every connected player in a single packet.
	@within EffectServer
	@param batch {EffectEntry}
]=]
function EffectServer.EffectsAll(batch: { EffectEntry })
	effectsSignal:FireAll(batch)
end

--[=[
	Plays each effect in `batch` for each player in `players` in a single packet.
	@within EffectServer
	@param players {Player}
	@param batch {EffectEntry}
]=]
function EffectServer.EffectsFor(players: { Player }, batch: { EffectEntry })
	effectsSignal:FireFor(players, batch)
end

--[=[
	Plays each effect in `batch` for every connected player except `ignorePlayer`.
	@within EffectServer
	@param ignorePlayer Player
	@param batch {EffectEntry}
]=]
function EffectServer.EffectsExcept(ignorePlayer: Player, batch: { EffectEntry })
	effectsSignal:FireExcept(ignorePlayer, batch)
end

return EffectServer
