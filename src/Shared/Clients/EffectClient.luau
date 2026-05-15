--[=[
	@class EffectClient
	Client-side receiver and dispatcher for cosmetic effects. Looks up effect modules by name
	in `ReplicatedStorage.Shared.Effects` and invokes them with the provided `args`. The same
	dispatch path is also exposed as `EffectClient.Effect` (single) and `EffectClient.Effects`
	(batch) for client-initiated local-only effects (UI feedback, prediction sparkles, etc.)
	that don't need a server round-trip.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)

local EffectClient = {}

--[=[
	@interface EffectEntry
	@within EffectClient
	@field Name string
	@field Args any
]=]
export type EffectEntry = { Name: string, Args: any }

local effects: { [string]: (any) -> () } = {}

local function runEffect(effectName: string, args: any)
	local effect = effects[effectName]
	if effect == nil then
		warn(`EffectClient: unknown effect {effectName}`)
		return
	end

	effect(args)
end

local function runEffects(batch: { EffectEntry })
	for _, entry in batch do
		runEffect(entry.Name, entry.Args)
	end
end

function EffectClient.Init()
	for _, module in ReplicatedStorage.Shared.Effects:GetChildren() do
		if module:IsA("ModuleScript") then
			effects[module.Name] = require(module) :: any
		end
	end

	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Effect")
	clientComm:GetSignal("Effect"):Connect(runEffect)
	clientComm:GetSignal("Effects"):Connect(runEffects)
end

--[=[
	Runs `effectName` locally on the client. Use for client-initiated effects that don't
	need to be authored by the server.
	@within EffectClient
	@param effectName string
	@param args any
]=]
function EffectClient.Effect(effectName: string, args: any)
	runEffect(effectName, args)
end

--[=[
	Runs each effect in `batch` locally on the client. Use for client-initiated effects
	that don't need to be authored by the server.
	@within EffectClient
	@param batch {EffectEntry}
]=]
function EffectClient.Effects(batch: { EffectEntry })
	runEffects(batch)
end

return EffectClient
