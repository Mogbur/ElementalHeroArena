-- ForgeVFX.server.lua  (place in ServerScriptService/RojoServer/Systems)
-- Server-side VFX + prompt hook for the Elemental Forge

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- Remotes (created elsewhere by ForgeRF)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local OpenForgeUI = Remotes and Remotes:FindFirstChild("OpenForgeUI")

-- Colors
local WHITE = Color3.new(1, 1, 1)
local FIRE  = Color3.fromRGB(255, 90, 60)
local EARTH = Color3.fromRGB(170,130,90)
local WATER = Color3.fromRGB( 80,140,255)

-- Utility: tag any effect part to be non-physical
local function tagEffect(p)
	if not p or not p:IsA("BasePart") then return end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	pcall(function() p.CollisionGroup = "Effects" end)
end

-- Utility: find the first BasePart under an instance
local function firstPart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

-- Beams
local function mkBeam(a0, a1, c0, c1, width, parent)
	if not (a0 and a1) then return nil end
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 40
	b.Width0 = width
	b.Width1 = width
	b.Color = ColorSequence.new(
		ColorSequenceKeypoint.new(0, c0),
		ColorSequenceKeypoint.new(0.5, c0:Lerp(c1, 0.5)),
		ColorSequenceKeypoint.new(1, c1)
	)
	b.Transparency = NumberSequence.new(
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 0)
	)
	b.Parent = parent
	return b
end

-- Ring pulse (for appear/vanish)
local function portalPulse(cf, appear, t, parent)
	local ring = Instance.new("Part")
	ring.Name = "PortalRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 0.2, 0.2)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(210, 240, 255)
	ring.Transparency = appear and 0.4 or 0.15
	ring.CFrame = cf * CFrame.Angles(0, math.rad(90), 0) -- lay flat
	tagEffect(ring)
	ring.Parent = parent

	local goal = appear
		and { Size = Vector3.new(12, 0.2, 12), Transparency = 0.15 }
		or  { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }

	TweenService:Create(ring, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(ring, t + 0.25)
end

-- Find the plot that contains this model (plots have an OwnerUserId attribute)
local function plotOf(inst)
	local cur = inst
	while cur do
		if cur:IsA("Model") and cur:GetAttribute("OwnerUserId") ~= nil then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- Core setup for a single ElementalForge model
local function setupForge(Forge) -- Forge is a Model named "ElementalForge"
	if not (Forge and Forge:IsA("Model")) then return end

	-- Required pieces in the template
	local EPylon = Forge:FindFirstChild("ElementalPylon")
	local SmallSphere = EPylon and EPylon:FindFirstChild("ElementalSphere")
	local FirePylon  = Forge:FindFirstChild("FirePylon")
	local EarthPylon = Forge:FindFirstChild("EarthPylon")
	local WaterPylon = Forge:FindFirstChild("WaterPylon")
	if not (SmallSphere and FirePylon and EarthPylon and WaterPylon) then
		warn("[ForgeVFX] Missing pylon parts under ElementalForge:", Forge:GetFullName())
		return
	end

	local origin = SmallSphere:FindFirstChild("BeamOrigin")
	local aFire  = FirePylon:FindFirstChild("Anchor_Fire")
	local aEarth = EarthPylon:FindFirstChild("Anchor_Earth")
	local aWater = WaterPylon:FindFirstChild("Anchor_Water")
	if not (origin and aFire and aEarth and aWater) then
		warn("[ForgeVFX] Missing attachments (BeamOrigin / Anchor_*).")
		return
	end

	-- Make beams
	local width = 1.8
	local beamSF = mkBeam(origin, aFire,  WHITE, FIRE,  width, Forge)
	local beamSE = mkBeam(origin, aEarth, WHITE, EARTH, width, Forge)
	local beamFW = mkBeam(aFire,  aWater, FIRE,  WATER, width, Forge)
	local beamEW = mkBeam(aEarth, aWater, EARTH, WATER, width, Forge)

	-- Add a white core + glass shell on the sphere
	local sp = firstPart(SmallSphere)
	if sp then
		local core = Instance.new("Part")
		core.Name = "EF_Core"
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(1, 1, 1)
		core.Material = Enum.Material.Neon
		core.Color = WHITE
		tagEffect(core)
		core.CFrame = sp.CFrame
		core.Parent = Forge

		local shell = Instance.new("Part")
		shell.Name = "EF_Shell"
		shell.Shape = Enum.PartType.Ball
		shell.Size = Vector3.new(1.8, 1.8, 1.8)
		shell.Material = Enum.Material.Glass
		shell.Transparency = 0.5
		shell.Color = WHITE
		tagEffect(shell)
		shell.CFrame = core.CFrame
		shell.Parent = Forge
	end

	-- Get the plot up front (so it's in scope for the prompt callback)
	local plot = plotOf(Forge)

	-- ProximityPrompt to open the existing UI
	local prompt = SmallSphere:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
	end
	prompt.ActionText = "Pray"
	prompt.ObjectText = "Elemental Forge"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = SmallSphere

	if OpenForgeUI then
		prompt.Triggered:Connect(function(player)
			-- Only the owner should be able to open; PlotService enforces ownership,
			-- but it’s fine if the UI opens for anyone while CombatLocked is true.
			if plot then
				OpenForgeUI:FireClient(player, plot)
			end
		end)
	else
		warn("[ForgeVFX] OpenForgeUI RemoteEvent not found.")
	end

	-- Show/Hide based on CombatLocked (forge visible while locked / between waves)
	local function setBeamsVisible(on)
		local alpha = on and 0.0 or 1.0
		for _, b in ipairs({ beamSF, beamSE, beamFW, beamEW }) do
			if b then
				b.Transparency = NumberSequence.new(
					NumberSequenceKeypoint.new(0, alpha),
					NumberSequenceKeypoint.new(1, alpha)
				)
			end
		end
	end

	local function show()
		setBeamsVisible(true)
		portalPulse(Forge:GetPivot(), true, 0.7, Forge)
	end

	local function hide()
		setBeamsVisible(false)
		portalPulse(Forge:GetPivot(), false, 0.8, Forge)
	end

	local function resync()
		if not plot then return end
		-- Visible while CombatLocked == true (pause/checkpoint)
		if plot:GetAttribute("CombatLocked") == true then
			show()
		else
			hide()
		end
	end

	if plot then
		plot:GetAttributeChangedSignal("CombatLocked"):Connect(resync)
	end
	task.defer(resync)
end

-- Watch all plots for an ElementalForge child
local function hookPlot(plotModel)
	if not (plotModel and plotModel:IsA("Model")) then return end

	-- If a forge already exists in this plot, set it up
	local existing = plotModel:FindFirstChild("ElementalForge")
	if existing and existing:IsA("Model") then
		setupForge(existing)
	end

	-- React to future adds
	plotModel.ChildAdded:Connect(function(ch)
		if ch:IsA("Model") and ch.Name == "ElementalForge" then
			setupForge(ch)
		end
	end)
end

-- Entry: hook current and future plots under workspace.Plots
local plotsFolder = workspace:FindFirstChild("Plots")
if plotsFolder then
	for _, p in ipairs(plotsFolder:GetChildren()) do
		hookPlot(p)
	end
	plotsFolder.ChildAdded:Connect(hookPlot)
else
	warn("[ForgeVFX] workspace.Plots folder not found.")
end
