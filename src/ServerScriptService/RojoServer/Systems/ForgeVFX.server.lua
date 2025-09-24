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

-- Beams (drop-in replacement)
local function mkBeam(a0, a1, c0, c1, width, parent)
	if not (a0 and a1) then return nil end
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera  = false           -- <-- don’t rotate with the camera
	b.Segments    = 40
	b.Width0      = width
	b.Width1      = width
	b.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   c0),
		ColorSequenceKeypoint.new(0.5, c0:Lerp(c1, 0.5)),
		ColorSequenceKeypoint.new(1,   c1)
	})
	-- stronger presence: less transparent overall
	b.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.10),
		NumberSequenceKeypoint.new(0.5, 0.40),
		NumberSequenceKeypoint.new(1,   0.10)
	})
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

-- ======= Fancy portal + full model fade helpers =======

local function setEffectPropsEnabled(inst, on)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Trail") then
			d.Enabled = on and true or false
		elseif d:IsA("Beam") then
			d.Enabled = on and true or false
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			-- tween brightness for lights (soften pop)
			local to = on and (d:GetAttribute("__EF_PreBright") or d.Brightness) or 0
			if on then
				if d:GetAttribute("__EF_PreBright") == nil then d:SetAttribute("__EF_PreBright", d.Brightness) end
			end
			TweenService:Create(d, TweenInfo.new(on and 0.6 or 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Brightness = to}):Play()
		elseif d:IsA("Decal") then
			local to = on and (d:GetAttribute("__EF_PreTrans") or d.Transparency) or 1
			if on then
				if d:GetAttribute("__EF_PreTrans") == nil then d:SetAttribute("__EF_PreTrans", d.Transparency) end
			end
			TweenService:Create(d, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = to}):Play()
		end
	end
end

local function fadeForgeBody(Forge: Model, makeVisible: boolean, dur: number)
	local ti = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(Forge:GetDescendants()) do
		if d:IsA("BasePart") then
			-- keep combat-safe
			d.CanCollide = false
			d.CanQuery   = false
			-- save original transparency once
			if d:GetAttribute("__EF_PreTrans") == nil then
				d:SetAttribute("__EF_PreTrans", d.Transparency)
			end
			local to = makeVisible and d:GetAttribute("__EF_PreTrans") or 1
			TweenService:Create(d, ti, {Transparency = to}):Play()
		elseif d:IsA("ProximityPrompt") then
			-- block open while hidden
			d.Enabled = makeVisible
		end
	end
	-- FX bits (beams/particles/lights/decals)
	setEffectPropsEnabled(Forge, makeVisible)
end

-- Big, layered portal burst (3 rings + a soft light pulse)
local function portalBurst(parent: Instance, cf: CFrame, appear: boolean, totalT: number)
	local folder = Instance.new("Folder")
	folder.Name = "EF_PortalFX"
	folder.Parent = parent

	-- helper to spawn one neon ring
	local function ring(sizeFrom, sizeTo, transFrom, transTo, t)
		local p = Instance.new("Part")
		p.Name = "Ring"
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(210, 240, 255)
		tagEffect(p)
		p.Size = Vector3.new(0.2, sizeFrom, sizeFrom)
		p.CFrame = cf * CFrame.Angles(0, math.rad(90), 0) -- lay flat
		p.Transparency = transFrom
		p.Parent = folder
		TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, sizeTo, sizeTo),
			Transparency = transTo,
		}):Play()
		Debris:AddItem(p, t + 0.25)
	end

	-- soft point light pulse at center
	local lightHolder = Instance.new("Part")
	lightHolder.Anchored, lightHolder.CanCollide, lightHolder.Transparency = true, false, 1
	lightHolder.Size = Vector3.new(0.5,0.5,0.5)
	lightHolder.CFrame = cf
	lightHolder.Parent = folder
	local lg = Instance.new("PointLight")
	lg.Color = Color3.fromRGB(185, 225, 255)
	lg.Range = 18; lg.Brightness = appear and 0 or 3
	lg.Parent = lightHolder
	local lt = TweenService:Create(lg, TweenInfo.new(totalT * 0.6, Enum.EasingStyle.Quad, appear and Enum.EasingDirection.Out or Enum.EasingDirection.In), {
		Brightness = appear and 3 or 0
	})
	lt:Play()

	-- timings: stagger the three rings a bit
	if appear then
		ring(2, 12, 0.7, 0.1, totalT*0.55)
		task.delay(totalT*0.10, function() ring(1.2, 9, 0.9, 0.15, totalT*0.50) end)
		task.delay(totalT*0.18, function() ring(0.8, 7, 0.95, 0.25, totalT*0.45) end)
	else
		-- vanish: pulse outward then collapse to nothing
		ring(8, 12, 0.2, 0.05, totalT*0.40)
		task.delay(totalT*0.40, function() ring(12, 0.6, 0.1, 1.0, totalT*0.60) end)
	end

	Debris:AddItem(folder, totalT + 0.8)
end

-- one-liner wrappers you’ll call from resync()
local function showForgeFancy(Forge: Model, appearT: number)
	appearT = appearT or 1.2
	portalBurst(Forge, Forge:GetPivot(), true, appearT)
	fadeForgeBody(Forge, true, appearT)
end

local function hideForgeFancy(Forge: Model, vanishT: number)
	vanishT = vanishT or 3.0
	portalBurst(Forge, Forge:GetPivot(), false, vanishT)
	fadeForgeBody(Forge, false, vanishT)
end

-- Core setup for a single ElementalForge model
local function setupForge(Forge) -- Forge is a Model named "ElementalForge"
	if not (Forge and Forge:IsA("Model")) then return end

	-- === match your Explorer names ===
	-- ElementalPylon / ElementalCrystal (with BeamOrigin under it)
	local EPylon         = Forge:FindFirstChild("ElementalPylon")
	local CornerCrystal  = EPylon and EPylon:FindFirstChild("ElementalCrystal")

	-- The three stone pylons with anchor attachments
	local FirePylon      = Forge:FindFirstChild("FirePylon")
	local EarthPylon     = Forge:FindFirstChild("EarthPylon")
	local WaterPylon     = Forge:FindFirstChild("WaterPylon")

	if not (EPylon and CornerCrystal and FirePylon and EarthPylon and WaterPylon) then
		warn("[ForgeVFX] Missing pylon parts under ElementalForge:", Forge:GetFullName())
		return
	end

	-- === attachments ===
	-- BeamOrigin lives under the *corner* crystal (your intent)
	local origin = CornerCrystal:FindFirstChild("BeamOrigin", true)
	local aFire  = FirePylon:FindFirstChild("Anchor_Fire",  true)
	local aEarth = EarthPylon:FindFirstChild("Anchor_Earth", true)
	local aWater = WaterPylon:FindFirstChild("Anchor_Water", true)

	-- If BeamOrigin is missing, create one on the crystal's first BasePart
	if not origin then
		local crystalPart = firstPart(CornerCrystal)
		if crystalPart then
			origin = Instance.new("Attachment")
			origin.Name = "BeamOrigin"
			origin.Parent = crystalPart
		end
	end

	if not (origin and aFire and aEarth and aWater) then
		warn("[ForgeVFX] Missing attachments (BeamOrigin / Anchor_*).")
		return
	end

	-- === beams (corner -> fire, corner -> earth, fire -> water, earth -> water) ===
	local width  = 1.8
	local beamSF = mkBeam(origin, aFire,  WHITE, FIRE,  width, Forge)
	local beamSE = mkBeam(origin, aEarth, WHITE, EARTH, width, Forge)
	local beamFW = mkBeam(aFire,  aWater, FIRE,  WATER, width, Forge)
	local beamEW = mkBeam(aEarth, aWater, EARTH, WATER, width, Forge)
	local beams  = { beamSF, beamSE, beamFW, beamEW }

	-- === prompt lives on the small corner crystal ===
	local promptParent = firstPart(CornerCrystal)
	local prompt = (promptParent and promptParent:FindFirstChildOfClass("ProximityPrompt")) or Instance.new("ProximityPrompt")
	prompt.ActionText = "Pray"
	prompt.ObjectText = "Elemental Forge"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode  = Enum.KeyCode.ButtonX   -- PS Cross / Xbox X
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent

	-- Get the plot up front (so it's in scope for the prompt callback)
	local plot = plotOf(Forge)

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

		-- === visibility + portal tied to CombatLocked ===
	local function resync()
		local plot = plotOf(Forge)
		if not plot then return end
		local locked = (plot:GetAttribute("CombatLocked") == true)
		if locked then
			-- BETWEEN waves (checkpoint, before starting): show with portal
			showForgeFancy(Forge, 1.2)
		else
			-- DURING waves: hide whole forge with a big 3s vanish
			hideForgeFancy(Forge, 3.0)
		end
	end

	-- run once and wire to future changes
	local plotForSignal = plotOf(Forge)
	if plotForSignal then
		plotForSignal:GetAttributeChangedSignal("CombatLocked"):Connect(resync)
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
