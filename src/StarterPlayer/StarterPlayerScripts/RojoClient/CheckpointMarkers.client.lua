-- CheckpointMarkers.client.lua
-- Finds every Plot's CheckpointMarker and:
--  • builds a local Billboard number
--  • rotates the ring + bounces the number
--  • pulses on checkpoint change
-- Expects each plot: Plots/<Plot>/Arena/CheckpointMarker/{Ring, NumberCore, Base}

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")
local PlotsFolder = Workspace:WaitForChild("Plots")

-- tunables
local ROT_SPEED_DEG   = 18       -- ring spin speed
local BOUNCE_H        = 0.35     -- studs
local BOUNCE_SPEED_HZ = 1.6
local VIEW_DISTANCE    = 220     -- only animate when camera is near

-- per-plot state
local markers = {}  -- [plot] = { ring, core, billboard, label, baseRingCF, baseCoreCF, t }

local function mkBillboard(core: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CheckpointBillboard"
	gui.Adornee = core
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(120, 120)
	gui.MaxDistance = 500
	gui.ExtentsOffsetWorldSpace = Vector3.new(0, 0.2, 0)
	gui.Parent = PG

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Text = "1"
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0
	lbl.TextStrokeColor3 = Color3.fromRGB(25, 70, 85)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = false
	lbl.TextSize = 60
	lbl.Parent = gui

	return gui, lbl
end

local function pulse(label: TextLabel, ring: BasePart)
	-- brief size pop + ring flash (local-only visuals)
	local up = TweenService:Create(label, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {TextSize = 74})
	local dn = TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextSize = 60})
	local oldT = ring.Transparency
	ring.Transparency = math.clamp((oldT or 0.2) - 0.12, 0, 1)
	up:Play()
	up.Completed:Once(function()
		dn:Play()
		task.delay(0.18, function()
			if ring and ring.Parent then ring.Transparency = oldT end
		end)
	end)
end

local function setupMarkerForPlot(plot: Instance)
	if markers[plot] then return end

	local arena = plot:FindFirstChild("Arena")
	if not arena then return end
	local marker = arena:FindFirstChild("CheckpointMarker")
	if not marker then return end

	local ring = marker:FindFirstChild("Ring")
	local core = marker:FindFirstChild("NumberCore")
	if not (ring and core) then return end
	if not ring:IsA("BasePart") or not core:IsA("BasePart") then return end

	local gui, label = mkBillboard(core)
	local cp = plot:GetAttribute("UnlockedCheckpoint") or 1
	label.Text = tostring(cp)

	local rec = {
		ring = ring,
		core = core,
		gui = gui,
		label = label,
		baseRingCF = ring.CFrame,
		baseCoreCF = core.CFrame,
		t = 0,
	}
	markers[plot] = rec

	-- react to attribute changes on THIS plot
	plot:GetAttributeChangedSignal("UnlockedCheckpoint"):Connect(function()
		local v = plot:GetAttribute("UnlockedCheckpoint")
		if v ~= nil then
			label.Text = tostring(v)
			pulse(label, ring)
		end
	end)
end

-- initial + future plots
for _, plot in ipairs(PlotsFolder:GetChildren()) do
	setupMarkerForPlot(plot)
end
PlotsFolder.ChildAdded:Connect(setupMarkerForPlot)

-- animation loop (distance-gated)
RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	for plot, rec in pairs(markers) do
		if rec.ring and rec.core and rec.ring.Parent and rec.core.Parent then
			local dist = (rec.ring.Position - camPos).Magnitude
			if dist <= VIEW_DISTANCE then
				rec.t += dt
				-- rotate ring around its own Y; bounce the core
				local angle = math.rad(ROT_SPEED_DEG) * rec.t
				rec.ring:PivotTo(rec.baseRingCF * CFrame.Angles(0, angle, 0))
				local y = math.sin(rec.t * math.pi * 2 * BOUNCE_SPEED_HZ) * BOUNCE_H
				rec.core:PivotTo(rec.baseCoreCF * CFrame.new(0, y, 0))
			end
		end
	end
end)
