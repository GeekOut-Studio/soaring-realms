--!strict

--[=[
	@class BillboardsHost
	App-level renderer that mirrors the `Billboards` registry into React state and
	renders one `BillboardGui` per entry. On `Billboards.Changed`, calls
	`setBillboards(Billboards.GetAll())`; the registry's immutable updates ensure
	the table reference differs each time so React re-renders.

	Live state updates inside a provider's `Render` callback go through React's
	normal reconciliation and do not flow through this host.

	The provider's `Native` overrides the host's defaults; the host then forces
	`Adornee = entry.Adornee` (last wins), so providers cannot accidentally
	de-anchor their own billboard.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Sift = require(ReplicatedStorage.Packages.Sift)

local Billboards = require(ReplicatedStorage.Shared.React.Billboards.Billboards)

local e = React.createElement
local merge = Sift.Dictionary.merge

local DEFAULTS = {
	Size = UDim2.fromScale(4, 1),
	StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
	LightInfluence = 0,
	AlwaysOnTop = true,
	MaxDistance = 60,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}

local function BillboardsHost(): any
	local billboards, setBillboards = React.useState(Billboards.GetAll())

	React.useEffect(function()
		local connection = Billboards.Changed:Connect(function()
			setBillboards(Billboards.GetAll())
		end)
		-- Re-sync once in case entries were added between mount and effect.
		setBillboards(Billboards.GetAll())
		return function()
			connection:Disconnect()
		end
	end, {})

	local children: { [string]: any } = {}
	for key, entry in billboards do
		children[key] = e("BillboardGui", merge(merge(DEFAULTS, entry.Native or {}), { Adornee = entry.Adornee }), {
			Content = entry.Render(),
		})
	end

	return e(React.Fragment, nil, children)
end

return BillboardsHost
