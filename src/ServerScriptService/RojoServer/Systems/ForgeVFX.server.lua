local TS = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:FindFirstChild("Remotes")
local OpenForgeUI = Remotes and Remotes:FindFirstChild("OpenForgeUI")

local WHITE = Color3.new(1,1,1)
local FIRE  = Color3.fromRGB(255, 90, 60)
local EARTH = Color3.fromRGB(170,130,90)
local WATER = Color3.fromRGB( 80,140,255)

local function tagEffect(p: BasePart)
	p.Anchored = true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
	pcall(function() p.CollisionGroup = "Effects" end)
end

local function firstPart(inst: Instance?): BasePart?
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	for _,d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then return d end end
	return nil
end

local function mkBeam(a0: Attachment, a1: Attachment, c0: Color3, c1: Color3, w: number, parent: Instance)
	local b = Instance.new("Beam")
	b.Attachment0 = a0; b.Attachment1 = a1
	b.FaceCamera = true; b.Segments = 40
	b.Width0 = w; b.Width1 = w
	b.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c0),
		ColorSequenceKeypoint.new(0.5, c0:Lerp(c1, 0.5)),
		ColorSequenceKeypoint.new(1, c1)
	})
	b.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 0)
	})
	b.Parent = parent
	return b
end

local function portalPulse(cf: CFrame, appear: boolean, t: number, parent: Instance)
	local ring = Instance.new("Part")
	ring.Name="PortalRing"; ring.Shape=Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 0.2, 0.2)
	ring.Material=Enum.Material.Neon
	ring.Color = Color3.fromRGB(210,240,255)
	ring.Transparency = appear and 0.4 or 0.15
	ring.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
	tagEffect(ring); ring.Parent = parent

	local goal = appear and {Size=Vector3.new(12,0.2,12), Transparency=0.15}
	                      or  {Size=Vector3.new(0.2,0.2,0.2), Transparency=1}
	TS:Create(ring, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	 :Play()
	game:GetService("Debris"):AddItem(ring, t + 0.2)
end

local function plotOf(inst: Instance?): Model?
	local cur=inst
	while cur do
		if cur:IsA("Model") and cur:GetAttribute("OwnerUserId")~=nil then return cur end
		cur=cur.Parent
	end
end

local function setupForge(Forge: Model)
	local EPylon = Forge:FindFirstChild("ElementalPylon")
	local SmallSphere = EPylon and EPylon:FindFirstChild("ElementalSphere")
	local FirePylon  = Forge:FindFirstChild("FirePylon")
	local EarthPylon = Forge:FindFirstChild("EarthPylon")
	local WaterPylon = Forge:FindFirstChild("WaterPylon")
	if not (SmallSphere and FirePylon and EarthPylon and WaterPylon) then return end

	local origin = SmallSphere:FindFirstChild("BeamOrigin") :: Attachment
	local aFire  = FirePylon:FindFirstChild("Anchor_Fire")  :: Attachment
	local aEarth = EarthPylon:FindFirstChild("Anchor_Earth"):: Attachment
	local aWater = WaterPylon:FindFirstChild("Anchor_Water"):: Attachment
	if not (origin and aFire and aEarth and aWater) then return end

	local width = 1.8
	local beamSF = mkBeam(origin, aFire,  WHITE, FIRE,  width, Forge)
	local beamSE = mkBeam(origin, aEarth, WHITE, EARTH, width, Forge)
	local beamFW = mkBeam(aFire,  aWater, FIRE,  WATER, width, Forge)
	local beamEW = mkBeam(aEarth, aWater, EARTH, WATER, width, Forge)

	-- white orb on the small sphere
	local sp = firstPart(SmallSphere)
	if sp then
		local core = Instance.new("Part"); core.Name="EF_Core"
		core.Shape=Enum.PartType.Ball; core.Size=Vector3.new(1,1,1)
		core.Material=Enum.Material.Neon; core.Color=WHITE
		tagEffect(core); core.CFrame = sp.CFrame; core.Parent=Forge

		local shell = Instance.new("Part"); shell.Name="EF_Shell"
		shell.Shape=Enum.PartType.Ball; shell.Size=Vector3.new(1.8,1.8,1.8)
		shell.Material=Enum.Material.Glass; shell.Transparency=0.5; shell.Color=WHITE
		tagEffect(shell); shell.CFrame = core.CFrame; shell.Parent=Forge
	end

	-- ProximityPrompt (E → open your existing UI)
	local prompt = SmallSphere:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText="Pray"; prompt.ObjectText="Elemental Forge"; prompt.KeyboardKeyCode=Enum.KeyCode.E
	prompt.HoldDuration=0; prompt.MaxActivationDistance=10; prompt.RequiresLineOfSight=false
	prompt.Parent = SmallSphere
	if OpenForgeUI then
        prompt.Triggered:Connect(function(player)
            OpenForgeUI:FireClient(player, plot) -- send plot (what your UI expects)
        end)
    end

	-- appear/vanish based on CombatLocked
	local plot = plotOf(Forge)
	local function show()
		portalPulse(Forge:GetPivot(), true, 0.7, Forge)
		for _, b in ipairs({beamSF,beamSE,beamFW,beamEW}) do b.Transparency = NumberSequence.new(0.0) end
	end
	local function hide()
		portalPulse(Forge:GetPivot(), false, 3.2, Forge)
		for _, b in ipairs({beamSF,beamSE,beamFW,beamEW}) do b.Transparency = NumberSequence.new(1.0) end
	end
	local function resync()
		if not plot then return end
		if plot:GetAttribute("CombatLocked") == false then hide() else show() end
	end
	if plot then plot:GetAttributeChangedSignal("CombatLocked"):Connect(resync) end
	task.defer(resync)
end

-- Watch plots for ElementalForge appearance
local plots = workspace:FindFirstChild("Plots")
if plots then
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") then
			plot.ChildAdded:Connect(function(ch)
				if ch.Name == "ElementalForge" and ch:IsA("Model") then setupForge(ch) end
			end)
			local f = plot:FindFirstChild("ElementalForge")
			if f and f:IsA("Model") then setupForge(f) end
		end
	end
end
