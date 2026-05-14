--!strict

--[=[
	@class ActionPrompts
	Helpers and constants for the `ProximityPrompt`s that start `Outworlder`
	actions (mining, woodcutting, …). Action prompts are tagged so the client-side
	`ActionPromptClient` can gate their local `.Enabled` on the local player's
	`InAction` state.

	Two layers express the same intent and must stay in lockstep:
	- `prompt.Enabled` (server-side) — the engine-level gate. `Triggered` only
	  fires on the server when this is `true`, so it's the authoritative defense
	  against a malicious client flipping its local `.Enabled`.
	- `ServerEnabled` attribute (replicated) — the client gate reads this to
	  decide local visibility while ignoring the local `.Enabled` (which it
	  writes itself).

	Owners must route every intent change through `SetServerEnabled` so the two
	stay atomic; otherwise the engine and the client gate can disagree.
]=]

local ActionPrompts = {}

--[=[
	@prop Tag "ActionPrompt"
	@within ActionPrompts
	The `CollectionService` tag applied to every action prompt.
]=]
ActionPrompts.Tag = "ActionPrompt"

--[=[
	@prop Attribute "ServerEnabled"
	@within ActionPrompts
	The attribute name carrying the server's enabled intent.
]=]
ActionPrompts.Attribute = "ServerEnabled"

--[=[
	Sets both `prompt.Enabled` and the `ServerEnabled` attribute atomically.
	Warns (does not error) if the prompt is missing the action-prompt tag —
	non-action prompts shouldn't be going through this helper, but a stale call
	site shouldn't crash the server either.
	@within ActionPrompts
	@param prompt ProximityPrompt
	@param value boolean
]=]
function ActionPrompts.SetServerEnabled(prompt: ProximityPrompt, value: boolean)
	if not prompt:HasTag(ActionPrompts.Tag) then
		warn(
			`ActionPrompts.SetServerEnabled called on a prompt missing tag "{ActionPrompts.Tag}": {prompt:GetFullName()}`
		)
	end
	prompt.Enabled = value
	prompt:SetAttribute(ActionPrompts.Attribute, value)
end

return ActionPrompts
