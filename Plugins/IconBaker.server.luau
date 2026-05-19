-- IconBaker — companion to scripts/lune/bake-icons.luau.
-- When the user clicks the toolbar button, this plugin polls a local HTTP
-- server (lune) for items to bake. For each item it renders the model in a
-- fullscreen ViewportFrame, calls CaptureService:CaptureScreenshot to drop a
-- PNG into %LOCALAPPDATA%\Roblox\InternalCaptures\, then signals lune so it
-- can pick up the file.
--
-- Install by building with rojo:
--   rojo build plugin.project.json -o "%LOCALAPPDATA%\Roblox\Plugins\IconBaker.rbxm"
-- then reopen Studio.

local CaptureService = game:GetService("CaptureService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local LUNE_URL = "http://127.0.0.1:9876"
local PRE_CAPTURE_WAIT = 0.4
local CAMERA_FOV = 30
local CAMERA_DIRECTION = Vector3.new(1, 0.6, 1).Unit
local CAMERA_PADDING = 1.05 -- multiplier on bounding-sphere distance; tighten further via alpha bbox in python
local CUBIC_RATIO = 1.4 -- long/short under this ratio is considered roughly cubic — no reorientation

local toolbar = plugin:CreateToolbar("Icon Baker")
local button = toolbar:CreateButton("Bake Icons", "Drive the lune bake-icons script.", "rbxasset://textures/ui/GuiImagePlaceholder.png")

local function postJson(path: string, payload: any): boolean
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = LUNE_URL .. path,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload),
		})
	end)
	if not ok then
		warn(string.format("[IconBaker] POST %s failed: %s", path, tostring(response)))
		return false
	end
	if not response.Success then
		warn(string.format("[IconBaker] POST %s -> %d %s", path, response.StatusCode, response.Body))
		return false
	end
	return true
end

local function getNextJob(): { kind: string?, assetPath: string?, done: boolean? }?
	local ok, response = pcall(function()
		return HttpService:RequestAsync({ Url = LUNE_URL .. "/next-job", Method = "GET" })
	end)
	if not ok then
		warn("[IconBaker] GET /next-job failed: " .. tostring(response))
		return nil
	end
	if not response.Success then
		warn(string.format("[IconBaker] GET /next-job -> %d", response.StatusCode))
		return nil
	end
	return HttpService:JSONDecode(response.Body)
end

local function resolveAssetPath(path: string): Instance?
	local assetsRoot = ServerStorage:FindFirstChild("Assets")
	if assetsRoot == nil then
		return nil
	end
	local current: Instance = assetsRoot
	for part in string.gmatch(path, "[^/]+") do
		local child = current:FindFirstChild(part)
		if child == nil then
			return nil
		end
		current = child
	end
	return current
end

local function computeBoundingBox(model: Instance): (Vector3, Vector3)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local cf, size = desc.CFrame, desc.Size
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local corner = cf * Vector3.new(x * size.X / 2, y * size.Y / 2, z * size.Z / 2)
						if corner.X < minX then
							minX = corner.X
						end
						if corner.X > maxX then
							maxX = corner.X
						end
						if corner.Y < minY then
							minY = corner.Y
						end
						if corner.Y > maxY then
							maxY = corner.Y
						end
						if corner.Z < minZ then
							minZ = corner.Z
						end
						if corner.Z > maxZ then
							maxZ = corner.Z
						end
					end
				end
			end
		end
	end
	local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	return center, size
end

local function captureCurrentScreen(): string?
	local done = false
	local err: string? = nil
	CaptureService:CaptureScreenshot(function(contentId)
		if contentId == nil or contentId == "" then
			err = "callback returned empty content id"
		end
		done = true
	end)
	local elapsed = 0
	while not done do
		task.wait(0.1)
		elapsed += 0.1
		if elapsed > 15 then
			return "CaptureScreenshot callback never fired"
		end
	end
	return err
end

local function renderAndCapture(kind: string, assetPath: string): boolean
	local source = resolveAssetPath(assetPath)
	if source == nil then
		postJson("/error", { kind = kind, message = "AssetPath not found: " .. assetPath })
		return false
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IconBakerCapture"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2147483647
	screenGui.ResetOnSpawn = false

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Color3.new(1, 1, 1)
	viewport.BorderSizePixel = 0
	viewport.Parent = screenGui

	local cloned = source:Clone()
	if cloned:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		cloned.Parent = wrapper
		cloned = wrapper
	end
	cloned.Parent = viewport

	local center, size = computeBoundingBox(cloned)

	-- Identify longest / mid / shortest axes by AABB extent.
	local axes = {
		{ idx = 1, size = size.X },
		{ idx = 2, size = size.Y },
		{ idx = 3, size = size.Z },
	}
	table.sort(axes, function(a, b)
		return a.size > b.size
	end)
	local longestSize = axes[1].size
	local shortestSize = axes[3].size

	if longestSize / math.max(shortestSize, 1e-3) > CUBIC_RATIO then
		-- Elongated. Build the rotation in two stages: first align the long world axis with
		-- the screen diagonal, then twist around that axis to put the mid dim on the broad
		-- face. Polarity per axis matches the user's convention: +X / +Y end goes to top-right,
		-- but for Z we point the "front" (-Z in Roblox) to top-right.
		local axisVectors = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
		local srcLong = axisVectors[axes[1].idx]
		local srcMid = axisVectors[axes[2].idx]

		local F = -CAMERA_DIRECTION
		local R = F:Cross(Vector3.yAxis).Unit
		local U = R:Cross(F).Unit
		local diagDir = (R + U).Unit
		local midDir = F:Cross(diagDir).Unit
		local longTarget = if axes[1].idx == 3 then -diagDir else diagDir

		local function rotateFromTo(from: Vector3, to: Vector3): CFrame
			local d = math.clamp(from:Dot(to), -1, 1)
			if d > 0.9999 then
				return CFrame.identity
			end
			if d < -0.9999 then
				local seed = if math.abs(from.X) < 0.9 then Vector3.xAxis else Vector3.yAxis
				return CFrame.fromAxisAngle(from:Cross(seed).Unit, math.pi)
			end
			return CFrame.fromAxisAngle(from:Cross(to).Unit, math.acos(d))
		end

		local r1 = rotateFromTo(srcLong, longTarget)
		local srcMidRotated = r1:VectorToWorldSpace(srcMid)
		local projRot = (srcMidRotated - srcMidRotated:Dot(longTarget) * longTarget).Unit
		local projMid = (midDir - midDir:Dot(longTarget) * longTarget).Unit
		local cosA = math.clamp(projRot:Dot(projMid), -1, 1)
		local sinA = projRot:Cross(projMid):Dot(longTarget)
		local r2 = CFrame.fromAxisAngle(longTarget, math.atan2(sinA, cosA))

		local delta = r2 * r1
		-- Rotate around the AABB center via PivotTo. The pivot may not coincide with the AABB
		-- center, so compose: translate-to-origin, rotate, translate-back, then apply to pivot.
		cloned:PivotTo(CFrame.new(center) * delta * CFrame.new(-center) * cloned:GetPivot())

		center, size = computeBoundingBox(cloned)
	end

	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(CAMERA_FOV) / 2) * CAMERA_PADDING
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(center + CAMERA_DIRECTION * distance, center)
	camera.FieldOfView = CAMERA_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	screenGui.Parent = CoreGui

	-- White background pass.
	task.wait(PRE_CAPTURE_WAIT)
	local captureError = captureCurrentScreen()

	-- Black background pass. The renderer needs a beat to redraw the bg before the second capture.
	if captureError == nil then
		viewport.BackgroundColor3 = Color3.new(0, 0, 0)
		task.wait(PRE_CAPTURE_WAIT)
		captureError = captureCurrentScreen()
	end

	screenGui:Destroy()

	if captureError ~= nil then
		postJson("/error", { kind = kind, message = captureError })
		return false
	end

	return postJson("/captured", { kind = kind })
end

local running = false

button.Click:Connect(function()
	if running then
		warn("[IconBaker] already running")
		return
	end
	running = true
	button:SetActive(true)
	print("[IconBaker] starting bake loop")

	while true do
		local job = getNextJob()
		if job == nil then
			warn("[IconBaker] aborting (lune unreachable)")
			break
		end
		if job.done == true then
			print("[IconBaker] bake complete")
			break
		end
		if job.kind == nil or job.assetPath == nil then
			warn("[IconBaker] malformed job payload, stopping")
			break
		end
		print(string.format("[IconBaker] baking %s (%s)", job.kind, job.assetPath))
		local ok = renderAndCapture(job.kind, job.assetPath)
		if not ok then
			warn(string.format("[IconBaker] %s failed, moving on", job.kind))
		end
	end

	running = false
	button:SetActive(false)
end)
