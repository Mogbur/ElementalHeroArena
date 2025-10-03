-- CheckpointMarkers.client.lua  (world-sized number, no screen scaling)

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")

local LP = Players.LocalPlayer
local PlotsFolder = Workspace:WaitForChild("Plots")

-- tunables
local ROT_SPEED_DEG   = 8
local BOUNCE_H        = 0.15
local BOUNCE_SPEED_HZ = 0.7
local VIEW_DISTANCE   = 160

local markers = {}
local TAG = "[CheckpointMarkers]"

local function waveToCheckpointFromCleared(lastCleared: number?): number
	lastCleared = tonumber(lastCleared) or 0
	if lastCleared < 1 then return 1 end
	return ((lastCleared - 1) // 5) * 5 + 1
end

-- WORLD-SIZED NUMBER (SurfaceGui) -------------------------------------------
local function mkWorldNumber(core: BasePart)
	-- If your ring faces the +Z/-Z axis, Front will point at the player most of the time.
	-- Change Face if your NumberCore is oriented differently.
	local sg = Instance.new("SurfaceGui")
	sg.Name = "CheckpointSurface"
	sg.Adornee = core
	sg.Parent = core
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50               -- visual sharpness; doesn’t affect world size
	sg.CanvasSize = Vector2.new(128,128)
	sg.AlwaysOnTop = false              -- set true if you want it to draw through geometry

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Text = "1"
	lbl.TextColor3 = Color3.new(1,1,1)
	lbl.TextStrokeTransparency = 0
	lbl.TextStrokeColor3 = Color3.fromRGB(25,70,85)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = false              -- fixed text size (world-sized feel)
	lbl.TextSize = 75                   -- tweak to fit nicely inside your ring
	lbl.Parent = sg

	return sg, lbl
end

local function pulse(label: TextLabel, ring: BasePart?)
	-- quick size pop (UI-only) + optional ring flash
	local base = label.TextSize
	local up = TweenService:Create(label, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {TextSize = base + 20})
	local dn = TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextSize = base})

	local oldT
	if ring then oldT = ring.Transparency; ring.Transparency = math.clamp((oldT or 0.2) - 0.12, 0, 1) end

	up:Play()
	up.Completed:Once(function()
		dn:Play()
		task.delay(0.18, function()
			if ring and ring.Parent and oldT ~= nil then ring.Transparency = oldT end
		end)
	end)
end

local function cleanupPlot(plot)
	local rec = markers[plot]
	if not rec then return end
	if rec.gui then rec.gui:Destroy() end
	markers[plot] = nil
end

local function findMarkerPieces(plot: Instance)
	local arena  = (plot:IsA("Model") and (plot:FindFirstChild("Arena") or plot)) or nil
	if not arena then return end

	local marker = arena:FindFirstChild("CheckpointMarker", true)
	if not marker then return end

	local core = marker:FindFirstChild("NumberCore", true)
	if not (core and core:IsA("BasePart")) then return end

	local rings = {}
	for _, d in ipairs(marker:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:match("^Ring") then
			table.insert(rings, d)
		end
	end
	return marker, core, rings
end

local function setupMarkerForPlot(plot: Instance)
	if not plot:IsA("Model") or markers[plot] then return end

	local marker, core, rings = findMarkerPieces(plot)
	if not (marker and core) then
		plot.DescendantAdded:Connect(function(d)
			if markers[plot] then return end
			if d.Name == "CheckpointMarker" or d.Name == "NumberCore" or d.Name:match("^Ring") then
				task.defer(function() setupMarkerForPlot(plot) end)
			end
		end)
		return
	end

	local gui, label = mkWorldNumber(core)
	local cleared = tonumber(plot:GetAttribute("MaxClearedWave")) or 0
	local cp = waveToCheckpointFromCleared(cleared)
	label.Text = tostring(cp)

	local rec = {
		rings        = rings,
		core         = core,
		gui          = gui,
		label        = label,
		baseRingCFs  = {},
		baseCoreCF   = core.CFrame,
		t            = 0,
		lastShown    = cp,
	}
	for i, r in ipairs(rings) do rec.baseRingCFs[i] = r.CFrame end
	markers[plot] = rec

	print(TAG, "ready on", plot.Name, ("rings=%d"):format(#rings))

	-- owner-only prompt visibility (local)
	local prompt = core:FindFirstChild("CheckpointPrompt_Marker", true)
	local function refreshPrompt()
		local isOwner = (plot:GetAttribute("OwnerUserId") or 0) == LP.UserId
		if prompt then prompt.Enabled = isOwner end
	end
	refreshPrompt()
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshPrompt)

	plot:GetAttributeChangedSignal("MaxClearedWave"):Connect(function()
		local c = tonumber(plot:GetAttribute("MaxClearedWave")) or 0
		local newCP = waveToCheckpointFromCleared(c)
		if newCP ~= rec.lastShown then
			rec.lastShown = newCP
			rec.label.Text = tostring(newCP)
			pulse(rec.label, rec.rings[1])
		end
	end)

	plot.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanupPlot(plot) end
	end)
end

for _, p in ipairs(PlotsFolder:GetChildren()) do setupMarkerForPlot(p) end
PlotsFolder.ChildAdded:Connect(setupMarkerForPlot)

RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position

	for _, rec in pairs(markers) do
		local core = rec.core
		if core and core.Parent then
			local dist = (core.Position - camPos).Magnitude
			if dist <= VIEW_DISTANCE then
				rec.t += dt
				local angle = math.rad(ROT_SPEED_DEG) * rec.t
				local y     = math.sin(rec.t * math.pi * 2 * BOUNCE_SPEED_HZ) * BOUNCE_H

				-- Number bobs with the core (no resizing; it’s world-sized)
				-- inside RenderStepped, where you computed y/angle
				local basePos = rec.baseCoreCF.Position
				local pos     = basePos + Vector3.new(0, y, 0)                                -- world-space bob
				local face    = Vector3.new(camPos.X, pos.Y, camPos.Z)                         -- yaw-only target
				local look    = CFrame.lookAt(pos, face)                                       -- face camera
				core:PivotTo(look)                                                              -- <- no local offset

				-- Spin rings (alternate directions for style)
				for i, r in ipairs(rec.rings) do
					if r and r.Parent then
						local dir = ((i % 2) == 0) and -1 or 1
						r:PivotTo(rec.baseRingCFs[i] * CFrame.new(0, y, 0) * CFrame.Angles(0, dir * angle, 0))
					end
				end
			end
		end
	end
end)
