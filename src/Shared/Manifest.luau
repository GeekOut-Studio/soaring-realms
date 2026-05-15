--[=[
	@class Manifest
	Captures a snapshot of an instance hierarchy on one side and waits for the
	matching hierarchy to fully replicate on the other side. Built for the
	Roblox replication-race case where a `ChildAdded` listener fires the moment
	a model is parented, but its descendant parts trickle in over the following
	frames — measuring the model immediately yields wrong results.

	Typical use: the server captures a manifest of an asset at construct time,
	ships it inside an effect's args, and the client `Await`s the manifest
	before reading positions, bounding boxes, etc.

	Sibling instances with the same name are disambiguated by `Number`, a
	per-name 1-based count assigned in `GetChildren()` iteration order at
	`Make` time. `Await` waits for at least `Number` siblings of that name to
	exist under the parent; identity within a name-group is not preserved (and
	not needed for the replication-wait purpose).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)

local DEFAULT_TIMEOUT = 10

local Manifest = {}

--[=[
	@interface Node
	@within Manifest
	@field Name string
	@field Number number -- 1-based count among siblings sharing this name; always present (1 for unique-by-name nodes).
	@field Children {Node}
]=]
export type Node = {
	Name: string,
	Number: number,
	Children: { Node },
}

local function makeChildren(instance: Instance): { Node }
	local nameCounts: { [string]: number } = {}
	local children: { Node } = {}
	for _, child in instance:GetChildren() do
		local count = (nameCounts[child.Name] or 0) + 1
		nameCounts[child.Name] = count
		table.insert(children, {
			Name = child.Name,
			Number = count,
			Children = makeChildren(child),
		})
	end
	return children
end

--[=[
	Captures the full descendant tree of `instance` as a `Node`. The root
	node's `Name` is `instance.Name` and `Number` is `1`. No filtering — every
	descendant is included.
	@within Manifest
	@param instance Instance
	@return Node
]=]
function Manifest.Make(instance: Instance): Node
	return {
		Name = instance.Name,
		Number = 1,
		Children = makeChildren(instance),
	}
end

local function findNthByName(parent: Instance, name: string, n: number): Instance?
	local count = 0
	for _, child in parent:GetChildren() do
		if child.Name == name then
			count += 1
			if count == n then
				return child
			end
		end
	end
	return nil
end

local function awaitChild(parent: Instance, name: string, n: number)
	return Promise.new(function(resolve, _, onCancel)
		local existing = findNthByName(parent, name, n)
		if existing ~= nil then
			resolve(existing)
			return
		end
		local connection
		connection = parent.ChildAdded:Connect(function(child)
			if child.Name ~= name then
				return
			end
			local found = findNthByName(parent, name, n)
			if found ~= nil then
				connection:Disconnect()
				resolve(found)
			end
		end)
		onCancel(function()
			connection:Disconnect()
		end)
	end)
end

local function awaitTree(instance: Instance, node: Node)
	local promises = {}
	for _, childEntry in node.Children do
		table.insert(
			promises,
			awaitChild(instance, childEntry.Name, childEntry.Number):andThen(function(childInstance)
				return awaitTree(childInstance, childEntry)
			end)
		)
	end
	return Promise.all(promises):andThenReturn(instance)
end

--[=[
	Waits for `instance`'s descendant tree to match `manifest`. The root
	`instance` is trusted — `Await` doesn't validate its name against
	`manifest.Name`. Each child described by the manifest is awaited via
	`ChildAdded`, recursively, in parallel.

	Resolves with `instance` once every node in the manifest has a matching
	instance present. Rejects after `timeout` seconds if any leaf hasn't
	replicated.

	Sibling instances with the same name are awaited by count: a manifest
	saying "2 children named X" causes `Await` to resolve once at least 2 are
	present under that parent.
	@within Manifest
	@param instance Instance
	@param manifest Node
	@param timeout number? -- Defaults to 10 seconds.
	@return Promise -- Resolves with `instance`.
]=]
function Manifest.Await(instance: Instance, manifest: Node, timeout: number?)
	return awaitTree(instance, manifest):timeout(timeout or DEFAULT_TIMEOUT, "Manifest.Await: timed out")
end

return Manifest
