--[=[
	@class EffectServer
	Server-side dispatcher for cosmetic effects. Sends a named effect plus its `args` to one
	or more clients, where `EffectClient` looks the name up in `ReplicatedStorage.Shared.Effects`
	and runs the matching effect module. Effects are purely visual/audio — never put gameplay
	logic in an effect module.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)

local EffectServer = {}

local effectSignal

function EffectServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Effect")
	effectSignal = serverComm:CreateSignal("Effect")
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

return EffectServer
