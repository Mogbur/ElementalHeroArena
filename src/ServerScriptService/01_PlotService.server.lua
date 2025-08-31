-- PlotService.server.lua
-- Claims a plot, spawns/teleports the Hero, spawns waves, shows Victory/Defeat,
-- heals 50% between wins, and cleans leftovers. Enemies are sanitized so they
-- stand on the ground and actually path.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local PhysicsService    = game:GetService("PhysicsService")

local RSM        = ReplicatedStorage:WaitForChild("Modules")
local EnemyCommon   = require(RSM.Enemy.EnemyCommon)
local EnemyCatalog  = require(RSM.Enemy.EnemyCatalog)
local Waves = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Waves"):WaitForChild("Waves"))
local SkillConfig   = require(RSM.SkillConfig)
local SkillTuning   = require(RSM.SkillTuning)
local DamageNumbers = require(RSM.DamageNumbers)

local SSS   = game:GetService("ServerScriptService")
local SMods = SSS:WaitForChild("RojoServer"):WaitForChild("Modules")
local EnemyFactory = require(SMods.EnemyFactory)
local CollectionService = game:GetService("CollectionService")
local HeroBrain = require(SSS.RojoServer.Modules.HeroBrain)

-- Optional if you need them directly here:
-- local EnemyCommon  = require(RS.Enemy.EnemyCommon)
-- local EnemyCatalog = require(RS.Enemy.EnemyCatalog)

-- near the top of PlotService (after services)
task.spawn(function()
	while task.wait(5) do
		pcall(function() PhysicsService:CollisionGroupSetCollidable("Default", "Default", true) end)
	end
end)

-- One-time collision sanity: ensure Default collides with itself.
do
	local ok, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable("Default", "Default", true)
	end)
	if not ok then
		warn("[PlotService] Couldn't enforce Default<>Default collidable:", err)
	end
end
-- one-time: make "Hero" group exist and collide with Default
pcall(function() PhysicsService:RegisterCollisionGroup("Hero") end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable("Hero", "Default", true)
	PhysicsService:CollisionGroupSetCollidable("Hero", "Hero",   false)
end)

local HeroTemplate  = ServerStorage:WaitForChild("HeroTemplate")
local EnemyTemplate = ServerStorage:WaitForChild("EnemyTemplate")

-- === Place/anchor names ===
local PLOTS_CONTAINER   = workspace:WaitForChild("Plots")
local PLOT_NAME_PATTERN = "^BasePlot%d+$"
local SPAWN_ANCHOR      = "02_SpawnAnchor"
local HERO_IDLE_ANCHOR  = "03_HeroAnchor"
local PORTAL_ANCHOR     = "05_PortalAnchor"
local BANNER_ANCHOR     = "06_BannerAnchor" -- optional; falls back to portal
local ARENA_HERO_SPAWN  = "HeroSpawn"

-- Wave restart checkpoints (every N waves)
local WAVE_CHECKPOINT_INTERVAL = 5   -- 5 = restart to 1/6/11/...
local BANNER_HOLD_SEC = 5            -- how long DEFEAT / VICTORY floats

-- === Defaults on plots ===
local DEFAULT_ATTRS = {
	OwnerUserId  = 0,
	HeroLevel    = 1,
	PortalTier   = 1,
	Prestige     = 0,
	LastElement  = "Neutral",
	CurrentWave  = 1,
	AutoChain    = true,
	CritChance   = 0.03,
	CritMult     = 2.0,
}

-- === Fight tuning ===
local ENEMY_TTL_SEC       = 60
local BETWEEN_SPAWN_Z     = 4
local FIGHT_COOLDOWN_SEC  = 1.5
local CHECK_PERIOD        = 0.25
local BETWEEN_WAVES_DELAY = 1.25
local CHAIN_HARD_LIMIT    = 20
local HEAL_BETWEEN_WAVES  = 0.50 -- heal to at least 50%

-- Where your AI expects enemies to live (declare early so helpers can see it)
local ENEMIES_FOLDER_NAME = "Enemies"

-- ==== Totem SFX (swap to your own later) ====
local TOTEM_SFX = {
	count3 = 9125640290,
	count2 = 9125640290,
	count1 = 9125640290,
	go     = 9116427328,
}

-- === Forward declarations ===
local setSignpost

local pinFrozenHeroToIdleGround -- forward declaration

local function playAt(partOrPos, soundId, vol)
	if not soundId then return end
	local holder, isTemp
	if typeof(partOrPos) == "Instance" and partOrPos:IsA("BasePart") then
		holder = Instance.new("Attachment"); holder.Parent = partOrPos
	else
		holder = Instance.new("Part"); isTemp = true
		holder.Anchored, holder.CanCollide, holder.Transparency = true, false, 1
		holder.Size = Vector3.new(0.2,0.2,0.2)
		holder.CFrame = CFrame.new(typeof(partOrPos) == "Vector3" and partOrPos or Vector3.new())
		holder.Parent = workspace
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://"..tostring(soundId)
	s.Volume = vol or 0.9
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 90
	s.Parent = holder
	s:Play()
	s.Ended:Once(function() if isTemp and holder then holder:Destroy() end end)
	Debris:AddItem(holder, 5)
end

-- Freeze/thaw (kept for other uses)
local function setModelFrozen(model, on)
	if not model then return end
	local hum = model:FindFirstChildOfClass("Humanoid"); if not hum then return end

	-- SAFE animation toggle that works on all engine versions
	local function setAnimatorEnabled(h, enabled)
		local animator = h:FindFirstChildOfClass("Animator")
		if animator then
			if not enabled then
				-- stop any currently playing tracks
				for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
					pcall(function() t:Stop(0) end)
				end
			end
			-- Only touch Animator.Enabled if the property exists
			local ok, has = pcall(function() return animator.Enabled end)
			if ok then
				if not enabled then
					animator:SetAttribute("PreEnabled", has and 1 or 0)
					pcall(function() animator.Enabled = false end)
				else
					local pre = animator:GetAttribute("PreEnabled")
					pcall(function() animator.Enabled = (pre == nil) or (pre == 1) end)
					animator:SetAttribute("PreEnabled", nil)
				end
			end
		end
		-- Always toggle the classic Animate script
		local animate = h.Parent and h.Parent:FindFirstChild("Animate")
		if animate and animate:IsA("Script") then
			animate.Disabled = not enabled
		end
	end

	if on then
		-- cache
		if hum:GetAttribute("PreFreezeWS") == nil then hum:SetAttribute("PreFreezeWS", hum.WalkSpeed) end
		if hum:GetAttribute("PreFreezeJP") == nil then hum:SetAttribute("PreFreezeJP", hum.JumpPower) end

		setAnimatorEnabled(hum, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		hum.AutoRotate   = false
		hum.PlatformStand = true
		hum.WalkSpeed, hum.JumpPower = 0, 0

		for _, bp in ipairs(model:GetDescendants()) do
			if bp:IsA("BasePart") then
				if bp:GetAttribute("PreAnchored") == nil then
					bp:SetAttribute("PreAnchored", bp.Anchored and 1 or 0)
				end
				bp.Anchored = true
				bp.CanCollide = false                -- no collisions while frozen
				bp.AssemblyLinearVelocity  = Vector3.zero
				bp.AssemblyAngularVelocity = Vector3.zero
			elseif bp:IsA("AlignPosition") or bp:IsA("AlignOrientation") then
				bp.Enabled = false
			end
		end
	else
		setAnimatorEnabled(hum, true)
		hum.PlatformStand = false
		hum.AutoRotate    = true

		hum.WalkSpeed = hum:GetAttribute("PreFreezeWS") or 13
		hum.JumpPower = hum:GetAttribute("PreFreezeJP") or hum.JumpPower
		hum:SetAttribute("PreFreezeWS", nil)
		hum:SetAttribute("PreFreezeJP", nil)

		for _, bp in ipairs(model:GetDescendants()) do
			if bp:IsA("BasePart") then
				local pre = bp:GetAttribute("PreAnchored")
				if pre ~= nil then
					bp.Anchored = (pre == 1)
					bp:SetAttribute("PreAnchored", nil)
				end
				-- Only HRP collides for normal rigs
				bp.CanCollide = (bp.Name == "HumanoidRootPart")
				bp.AssemblyLinearVelocity  = Vector3.zero
				bp.AssemblyAngularVelocity = Vector3.zero
			end
		end

		pcall(function()
			hum:Move(Vector3.zero, true)
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
end



local function freezeEnemiesInPlot(plot, on)
	local folder = plot:FindFirstChild(ENEMIES_FOLDER_NAME, true)
	if not folder then return end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			setModelFrozen(m, on)
		end
	end
end

local function thawModelHard(model)
	local hum  = model and model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	for _, bp in ipairs(model:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			bp.AssemblyLinearVelocity  = Vector3.zero
			bp.AssemblyAngularVelocity = Vector3.zero
			bp.CollisionGroup = "Default"
		end
	end
	hum.PlatformStand, hum.AutoRotate, hum.Sit = false, true, false
	local ws = hum:GetAttribute("PreFreezeWS")
	local jp = hum:GetAttribute("PreFreezeJP")
	if ws then hum.WalkSpeed = ws elseif hum.WalkSpeed <= 0 then hum.WalkSpeed = 16 end
	if jp then hum.JumpPower = jp end
	hum:SetAttribute("PreFreezeWS", nil)
	hum:SetAttribute("PreFreezeJP", nil)
	hum:SetAttribute("PreFreezeAnchored", nil)
	pcall(function()
		hum:Move(Vector3.zero, true)
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

-- ==== Find your ArenaTotem pieces (robust to casing/nesting) ====
local function findTotem(plot)
	local m = plot:FindFirstChild("ArenaTotem", true)
	if not (m and m:IsA("Model")) then return nil end
	local gem = m:FindFirstChild("Gem")
	if not (gem and gem:IsA("BasePart")) then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower():find("gem") then gem = d; break end
		end
	end
	local shell = m:FindFirstChild("GemShell")
	local parts = m:FindFirstChild("Particles", true)
	local att   = parts and parts:FindFirstChildOfClass("Attachment")
	local light = parts and parts:FindFirstChildOfClass("PointLight")
	return { model = m, gem = gem, shell = shell, attachment = att, light = light }
end

local function pulseGem(totem)
	if not (totem and totem.gem and totem.gem:IsA("BasePart")) then return end
	local g = totem.gem
	local orig = g.Size
	local up = TweenService:Create(g, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = orig * 1.06})
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(g, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = orig}):Play()
	end)
	if totem.light then
		local b0 = totem.light.Brightness
		TweenService:Create(totem.light, TweenInfo.new(0.12), {Brightness = b0 + 1.2}):Play()
		task.delay(0.12, function()
			if totem.light then TweenService:Create(totem.light, TweenInfo.new(0.18), {Brightness = b0}):Play() end
		end)
	end
end

local function burstRays(totem, n)
	if not (totem and totem.attachment) then return end
	for _,pe in ipairs(totem.attachment:GetChildren()) do
		if pe:IsA("ParticleEmitter") then pe:Emit(n or 30) end
	end
end

-- === Remotes ===
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local RE_WaveText   = ensureRemote("WaveText")
ensureRemote("OpenEquipMenu")
ensureRemote("CastSkillRequest")
ensureRemote("SkillPurchaseRequest")
ensureRemote("SkillEquipRequest")
ensureRemote("DamageNumbers")      -- <— for heal + shield ticks
ensureRemote("SkillVFX")           -- if not already created
local RE_WaveBanner = ensureRemote("WaveBanner")

-- === State ===
local playerToPlot  = {} -- [Player] = Model
local plotToPlayer  = {} -- [Model]  = Player
local fightBusy     = {} -- [Model]  = bool
local lastTriggered = {} -- [Model]  = number

local function setCombatLock(plot, on)
	if plot and plot:GetAttribute("CombatLocked") ~= (on and true or false) then
		plot:SetAttribute("CombatLocked", on and true or false)
	end
end

-- === Helpers ===
local function getAnchor(plot, name) return plot:FindFirstChild(name, true) end

local function findHeroAnchor(plot)
	local exact = getAnchor(plot, HERO_IDLE_ANCHOR)
	if exact and exact:IsA("BasePart") then return exact end
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():find("heroanchor") then return d end
	end
end

local function getBannerAnchorPart(plot)
	local p = plot:FindFirstChild(BANNER_ANCHOR, true)
		or getAnchor(plot, BANNER_ANCHOR)
		or getAnchor(plot, PORTAL_ANCHOR)
		or findHeroAnchor(plot)
		or plot.PrimaryPart
	if p and p:IsA("BasePart") then return p end
	return nil
end

local function showWorldBanner(plot, text, bgColor, sec, kind)
	if not SHOW_WORLD_BANNER then return end
	local anchor = getBannerAnchorPart(plot)
	if not anchor then return end
	local palette = {
		wave    = {from = Color3.fromRGB( 70,130,220), to = Color3.fromRGB( 40, 90,200)},
		victory = {from = Color3.fromRGB( 90,210,140), to = Color3.fromRGB( 55,165,110)},
		defeat  = {from = Color3.fromRGB(230,110,100), to = Color3.fromRGB(185, 70, 70)},
	}
	local colors = palette[kind or "wave"]

	local gui = Instance.new("BillboardGui")
	gui.Name = "WaveBannerBillboard"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(760, 160)
	gui.ExtentsOffsetWorldSpace = Vector3.new(0, 35, 0)
	gui.Parent = plot

	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = Color3.fromRGB(0,0,0)
	shadow.BackgroundTransparency = 0.75
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(0, 6)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	shadow.Parent = gui
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 26)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = (bgColor or (colors and colors.to)) or Color3.fromRGB(60,110,200)
	frame.BackgroundTransparency = 0.0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromOffset(0, 0)
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 26)

	local grad = Instance.new("UIGradient")
	if not bgColor and colors then
		grad.Color = ColorSequence.new(colors.from, colors.to)
	else
		grad.Color = ColorSequence.new(frame.BackgroundColor3, frame.BackgroundColor3)
	end
	grad.Rotation = 30
	grad.Parent = frame

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Thickness = 2
	innerStroke.Transparency = 0.45
	innerStroke.Color = Color3.fromRGB(255,255,255)
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255,255,255)
	label.TextStrokeTransparency = 0.15
	label.TextStrokeColor3 = Color3.fromRGB(0,0,0)
	label.ZIndex = 2
	label.Parent = frame

	local poof = Instance.new("Frame")
	poof.AnchorPoint = Vector2.new(0.5, 0.5)
	poof.Position = UDim2.fromScale(0.5, 0.5)
	poof.Size = UDim2.fromScale(0.1, 0.1)
	poof.BackgroundColor3 = Color3.fromRGB(255,255,255)
	poof.BackgroundTransparency = 0.3
	poof.BorderSizePixel = 0
	poof.ZIndex = 0
	poof.Parent = frame
	Instance.new("UICorner", poof).CornerRadius = UDim.new(1, 0)

	local uiScale = Instance.new("UIScale", frame); uiScale.Scale = 0.9
	local pop = TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	pop:Play()

	local poofGrow = TweenService:Create(poof, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(1.25, 1.25), BackgroundTransparency = 1})
	poofGrow:Play()
	task.delay(0.28, function() if poof then poof:Destroy() end end)

	local up   = TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ExtentsOffsetWorldSpace = Vector3.new(0, 18.6, 0)})
	local down = TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),  {ExtentsOffsetWorldSpace = Vector3.new(0, 17.0, 0)})

	local t0 = time()
	task.spawn(function()
		while gui.Parent and (time() - t0) < (sec or 5) do
			up:Play();   up.Completed:Wait()
			down:Play(); down.Completed:Wait()
		end
		if gui then gui:Destroy() end
	end)
end

local function isPlot(m)
	if not m:IsA("Model") then return false end
	if m.Name:match(PLOT_NAME_PATTERN) then return true end
	return m:FindFirstChild("PlotGround", true)
		or m:FindFirstChild("Arena", true)
		or m:FindFirstChild(HERO_IDLE_ANCHOR, true)
end

local _ipairs, _tsort = ipairs, table.sort
local function getPlotsSorted()
	local list = {}
	for _, m in _ipairs(PLOTS_CONTAINER:GetChildren()) do
		if m:IsA("Model") and isPlot(m) then list[#list+1] = m end
	end
	_tsort(list, function(a, b)
		local an = a and a.Name or ""
		local bn = b and b.Name or ""
		return an:lower() < bn:lower()
	end)
	return list
end

local function ensureAttrs(plot)
	for k, v in pairs(DEFAULT_ATTRS) do
		if plot:GetAttribute(k) == nil then plot:SetAttribute(k, v) end
	end
end

local function ensureHeroBrain(hero)
	local ok, err = pcall(function() HeroBrain.attach(hero) end)
	if not ok then warn("[PlotService] HeroBrain.attach failed:", err) end
end

local function getHero(plot)
	local h = plot:FindFirstChild("Hero", true)
	if h and h:IsA("Model") and h:FindFirstChildOfClass("Humanoid") and h:FindFirstChild("HumanoidRootPart") then
		return h
	end
end

local function destroyHero(plot)
	local h = getHero(plot)
	if h then h:Destroy() end
end

local function freezeHeroAtIdle(plot)
	local hero = getHero(plot); if not hero then return end
	setModelFrozen(hero, true)
	hero:SetAttribute("BarsVisible", 0)       -- <— HIDE while idle
	hero:SetAttribute("ShieldHP", 0)
	hero:SetAttribute("ShieldMax", 0)
	hero:SetAttribute("ShieldExpireAt", 0)
	pinFrozenHeroToIdleGround(plot)
	task.delay(0.05, function() if hero and hero.Parent then pinFrozenHeroToIdleGround(plot) end end)
	task.delay(0.20, function() if hero and hero.Parent then pinFrozenHeroToIdleGround(plot) end end)
end

local function ensureHero(plot, ownerId)
	local existing = getHero(plot)
	if existing then ensureHeroBrain(existing); return existing end
	local clone = HeroTemplate:Clone()
	clone.Name = "Hero"
	clone:SetAttribute("IsHero", true)
	if ownerId then clone:SetAttribute("OwnerUserId", ownerId) end
	clone.Parent = plot

	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 13
		hum.AutoRotate = true
		hum.Sit = false
		hum.PlatformStand = false
		hum.BreakJointsOnDeath = false
	end
	for _, bp in ipairs(clone:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			bp.AssemblyLinearVelocity  = Vector3.zero
			bp.AssemblyAngularVelocity = Vector3.zero
			-- put new heroes in the proper group so they match your CollisionGroups script
			pcall(function() PhysicsService:SetPartCollisionGroup(bp, "Hero") end)
		end
	end

	ensureHeroBrain(clone)
	task.defer(function()
		local hrp = clone:FindFirstChild("HumanoidRootPart")
		if hrp then pcall(function() hrp:SetNetworkOwner(nil) end) end
	end)
	local idle = findHeroAnchor(plot) or getAnchor(plot, SPAWN_ANCHOR) or plot.PrimaryPart
	if idle then clone:PivotTo(idle.CFrame) end
	return clone
end

-- Return the Y of the top face of a BasePart (nil if not a BasePart)
local function topSurfaceY(part)
	if part and part:IsA("BasePart") then
		return part.Position.Y + (part.Size.Y * 0.5)
	end
	return nil
end

-- Probe several points and return the HIGHEST hit Y around a position.
local function probeGroundY(origin, exclude)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = exclude or {}

	local offsets = {
		Vector3.new(0,0,0),
		Vector3.new( 2,0, 0), Vector3.new(-2,0, 0),
		Vector3.new( 0,0, 2), Vector3.new( 0,0,-2),
	}

	local bestY
	for _, off in ipairs(offsets) do
		local start = origin + off + Vector3.new(0, 120, 0)
		local hit = workspace:Raycast(start, Vector3.new(0, -2000, 0), rp)
		if hit then
			bestY = bestY and math.max(bestY, hit.Position.Y) or hit.Position.Y
		end
	end
	return bestY or origin.Y
end

-- Stronger ground placement for hero (two-pass)
local function teleportHeroTo(plot, anchorName, opts)
	local hero = ensureHero(plot, plot:GetAttribute("OwnerUserId")); if not hero then return end
	local anchor = getAnchor(plot, anchorName)
	if not (anchor and anchor:IsA("BasePart")) then
		warn(("[PlotService] Missing anchor '%s' in %s"):format(anchorName, plot.Name))
		return
	end

	-- fully unfreeze before moving
	for _, bp in ipairs(hero:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			bp.AssemblyLinearVelocity  = Vector3.zero
			bp.AssemblyAngularVelocity = Vector3.zero
			pcall(function() PhysicsService:SetPartCollisionGroup(bp, "Hero") end)
		end
	end

	-- place roughly at the anchor first
	hero:PivotTo(anchor.CFrame + Vector3.new(0, 6, 0))

	local groundY = probeGroundY(anchor.Position, { hero })

	-- set feet on the ground using HipHeight + HRP half height
	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
	if hrp then
		local hip = (hum and hum.HipHeight) or 2
		if hip < 0.5 then hip = 2 end
		local targetY = groundY + hip + (hrp.Size.Y * 0.5)
		local deltaY  = targetY - hrp.Position.Y
		if math.abs(deltaY) > 1e-4 then
			hero:PivotTo(hero:GetPivot() + Vector3.new(0, deltaY, 0))
		end
	end

	if hum then
		hum.Sit = false
		hum.PlatformStand = false
		hum.AutoRotate = true
		hum:ChangeState(Enum.HumanoidStateType.Running)
		if opts and opts.fullHeal then hum.Health = hum.MaxHealth end
	end
	local hrp2 = hero:FindFirstChild("HumanoidRootPart")
	if hrp2 then pcall(function() hrp2:SetNetworkOwner(nil) end) end
end


local function toggleGroup(model, visible)
	if not model then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = visible and 0 or 1
			if not visible then d.CanCollide = false end
		elseif d:IsA("Decal") then
			d.Transparency = visible and 0 or 1
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = visible
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = visible
		end
	end
end

local function setVacantVisual(plot, vacant)
	local vac = plot:FindFirstChild("90_State_Vacant", true)
	if vac then toggleGroup(vac, vacant) end
	local active = plot:FindFirstChild("91_State_Active", true)
	if active then toggleGroup(active, not vacant) end
end

-- === Signpost (UI on board) ===
do
	local SIGNPOST_NAME, BOARD_PART_NAME, CANVAS_PART_NAME = "Signpost", "BoardFront", "SignCanvas"
	local FACE_MAP = {
		Front=Enum.NormalId.Front, Back=Enum.NormalId.Back, Left=Enum.NormalId.Left,
		Right=Enum.NormalId.Right, Top=Enum.NormalId.Top, Bottom=Enum.NormalId.Bottom
	}

	local function findBoardFront(signModel)
		if not signModel then return nil end
		local named = signModel:FindFirstChild(BOARD_PART_NAME, true)
		if named and named:IsA("BasePart") then return named end
		for _, d in ipairs(signModel:GetDescendants()) do
			if d:IsA("BasePart") then return d end
		end
	end

	local function getSignSurfaceParts(plot)
		local sign = plot:FindFirstChild(SIGNPOST_NAME)
		if not sign then return end
		local canvas = sign:FindFirstChild(CANVAS_PART_NAME, true)
		if canvas and canvas:IsA("BasePart") then
			return canvas, Enum.NormalId.Front
		end
		local board = findBoardFront(sign); if not board then return end
		local faceAttr = board:GetAttribute("BoardFace")
		local face = FACE_MAP[faceAttr] or Enum.NormalId.Front
		return board, face
	end

	function setSignpost(plot, player)
		local surfacePart, face = getSignSurfaceParts(plot); if not surfacePart then return end
		for _, c in ipairs(surfacePart:GetChildren()) do
			if (c:IsA("SurfaceGui") and c.Name == "BoardGui")
				or (c:IsA("BillboardGui") and c.Name == "OwnerCard") then
				c:Destroy()
			end
		end

		local gui = Instance.new("SurfaceGui"); gui.Name = "BoardGui"; gui.Parent = surfacePart
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.CanvasSize = Vector2.new(640, 220)
		gui.LightInfluence = 1
		gui.ClipsDescendants = true

		local root = Instance.new("Frame"); root.BackgroundTransparency = 1; root.Size = UDim2.fromScale(1, 1); root.Parent = gui

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.Cartoon
		title.TextColor3 = Color3.new(1,1,1)
		title.TextStrokeColor3 = Color3.new(0,0,0)
		title.TextStrokeTransparency = 0
		title.TextScaled = true
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(0.5, 0.2)
		title.Size = UDim2.fromScale(0.86, 0.24)
		title.Parent = root

		local stats = Instance.new("Frame")
		stats.BackgroundTransparency = 1
		stats.AnchorPoint = Vector2.new(0.5, 0.5)
		stats.Position = UDim2.fromScale(0.5, 0.52)
		stats.Size = UDim2.fromScale(0.86, 0.26)
		stats.Parent = root

		local v = Instance.new("UIListLayout", stats)
		v.FillDirection = Enum.FillDirection.Vertical
		v.HorizontalAlignment = Enum.HorizontalAlignment.Center
		v.VerticalAlignment = Enum.VerticalAlignment.Center
		v.Padding = UDim.new(0, 2)

		local function mk(txt, relH)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.Cartoon
			t.TextColor3 = Color3.new(1,1,1)
			t.TextStrokeColor3 = Color3.new(0,0,0)
			t.TextStrokeTransparency = 0
			t.Text = txt
			t.TextScaled = true
			t.TextXAlignment = Enum.TextXAlignment.Center
			t.Size = UDim2.new(1, 0, relH, 0)
			t.Parent = stats
		end

		local bottom = Instance.new("Frame")
		bottom.Name = "BottomBar"
		bottom.BackgroundTransparency = 1
		bottom.AnchorPoint = Vector2.new(0.5, 1)
		bottom.Position = UDim2.new(0.5, 0, 1, -6)
		bottom.Size = UDim2.new(1, -12, 0, 70)
		bottom.Parent = root

		if player then
			title.Text = ("%s's Plot"):format(player.DisplayName)
			mk(("Hero Lv. %d"):format(plot:GetAttribute("HeroLevel") or 1), 0.48)
			mk(("Prestige Lv. %d"):format(plot:GetAttribute("Prestige") or 0), 0.48)

			local faceImg = Instance.new("ImageLabel")
			faceImg.BackgroundTransparency = 1
			faceImg.Size = UDim2.fromOffset(64, 64)
			faceImg.Position = UDim2.new(0, 6, 0, 3)
			faceImg.ZIndex = 2
			faceImg.Parent = bottom
			Instance.new("UICorner", faceImg).CornerRadius = UDim.new(1, 0)
			local fs = Instance.new("UIStroke", faceImg); fs.Thickness = 2; fs.Color = Color3.new(0,0,0)

			local likes = plot:GetAttribute("Likes") or 0

			local plate = Instance.new("Frame")
			plate.Name = "LikePlate"
			plate.AnchorPoint = Vector2.new(0.5, 1)
			plate.Position = UDim2.new(0.5, 0, 1, 0)
			plate.Size = UDim2.new(0, 240, 0, 64)
			plate.BackgroundTransparency = 1
			plate.Parent = bottom
			local ps = Instance.new("UIStroke", plate); ps.Color = Color3.fromRGB(60,25,120); ps.Thickness = 3
			Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 10)

			local studBG = Instance.new("ImageLabel")
			studBG.Name = "StudBG"
			studBG.BackgroundTransparency = 1
			studBG.AnchorPoint = Vector2.new(0.5, 0.5)
			studBG.Position = UDim2.fromScale(0.5, 0.5)
			studBG.Size = UDim2.fromScale(1, 1)
			studBG.Image = "rbxassetid://6927295847"
			studBG.ScaleType = Enum.ScaleType.Tile
			studBG.TileSize = UDim2.fromOffset(26, 26)
			studBG.ImageColor3 = Color3.fromRGB(165,95,245)
			studBG.ImageTransparency = 0.1
			studBG.ZIndex = 1
			studBG.Parent = plate
			Instance.new("UICorner", studBG).CornerRadius = UDim.new(0, 10)

			local likeBtn = Instance.new("TextButton")
			likeBtn.Name = "LikeButton"
			likeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
			likeBtn.Position = UDim2.fromScale(0.5, 0.5)
			likeBtn.Size = UDim2.fromScale(1, 1)
			likeBtn.Text = ("👍  x%d"):format(likes)
			likeBtn.Font = Enum.Font.GothamBlack
			likeBtn.TextScaled = true
			likeBtn.TextColor3 = Color3.fromRGB(255,255,255)
			likeBtn.TextStrokeColor3 = Color3.fromRGB(0,0,0)
			likeBtn.TextStrokeTransparency = 0
			likeBtn.BackgroundColor3 = Color3.fromRGB(120,65,205)
			likeBtn.BackgroundTransparency = 0.28
			likeBtn.AutoButtonColor = true
			likeBtn.ZIndex = 2
			likeBtn.Parent = plate
			Instance.new("UICorner", likeBtn).CornerRadius = UDim.new(0, 10)
			local lbStroke = Instance.new("UIStroke", likeBtn); lbStroke.Thickness = 2; lbStroke.Color = Color3.fromRGB(60,25,120)

			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and url then faceImg.Image = url end
		else
			title.Text = "Empty Plot"
		end
	end
end

-- === Enemy helpers ===


local function enemiesAliveForPlot(plot)
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	local n = 0
	for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
		if m:GetAttribute("OwnerUserId") == ownerId then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum then
				if hum.Health > 0 then n += 1 end
			else
				local alive = (m:GetAttribute("Health") or 1) > 0
				if alive then n += 1 end
			end
		end
	end
	return n
end

local function ensureEnemyFolder(plot)
	local parent = plot:FindFirstChild("Arena") or plot
	local f = parent:FindFirstChild(ENEMIES_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = ENEMIES_FOLDER_NAME
		f.Parent = parent
	end
	return f
end

local function spawnWave(plot, portal)
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	local elem    = plot:GetAttribute("LastElement") or "Neutral"
	local waveIdx = plot:GetAttribute("CurrentWave") or 1
	local W = Waves.get(waveIdx)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}

	-- place & ground pin using **HRP** bottom (HRP is the collider)
	local function attachAntiSink(e, groundY)
		local hum = e:FindFirstChildOfClass("Humanoid"); if not hum then return end
		local hrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart; if not hrp then return end

		local bottomY = hrp.Position.Y - (hrp.Size.Y * 0.5)
		local deltaY  = (groundY + 0.05) - bottomY
		if math.abs(deltaY) > 1e-3 then
			e:PivotTo(e:GetPivot() + Vector3.new(0, deltaY, 0))
		end

		hum.PlatformStand = false
		hum.AutoRotate    = true
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
		pcall(function() hrp:SetNetworkOwner(nil) end)

		-- debug (one-shot)
		task.delay(0.1, function()
			print(("[SpawnDbg] root CanCollide=%s cg=%s bottomY=%.2f groundY=%.2f")
				:format(tostring(hrp.CanCollide), hrp.CollisionGroup, bottomY, groundY))
		end)
	end

	-- plan: [{kind="Basic", n=#}, {kind="Runner", n=#}, ...]
	local plan = { list = { { kind = "Basic", n = W.count } } }
if Waves and type(Waves.build) == "function" then
	plan = Waves.build({ wave = waveIdx, count = W.count })
else
	plan = { list = { { kind = "Basic", n = W.count } } }
end

	local enemyFolder = ensureEnemyFolder(plot)
	local spawnIndex  = 0

	for _, entry in ipairs(plan.list) do
		local kind = entry.kind   -- << fix undefined 'kind'
		for j = 1, entry.n do
			spawnIndex += 1

			local fwd     = portal.CFrame.LookVector
			local lateral = math.random(-6, 6)
			local dropPos = portal.Position - fwd * (8 + spawnIndex * BETWEEN_SPAWN_Z) + Vector3.new(lateral, 30, 0)

			local hit = workspace:Raycast(dropPos, Vector3.new(0, -1000, 0), rayParams)
			local groundY = (hit and hit.Position.Y) or portal.Position.Y
			local floorGroup = (hit and hit.Instance and hit.Instance:IsA("BasePart")) and hit.Instance.CollisionGroup or "Default"
			pcall(function() PhysicsService:CollisionGroupSetCollidable("Default", floorGroup, true) end)

			local lookAt = Vector3.new(dropPos.X, groundY + 2, dropPos.Z) - fwd
			local lookCF = CFrame.lookAt(Vector3.new(dropPos.X, groundY + 2, dropPos.Z), lookAt)

			local rank = (waveIdx % 5 == 0) and "MiniBoss" or nil

			-- EnemyFactory: stats & brain from catalog (single source of truth)
			local enemy = EnemyFactory.spawn(kind, ownerId, lookCF, groundY, enemyFolder, {
				elem = elem,
				rank = rank,
				wave = waveIdx,   -- factory does hp/dmg scaling
			})

			if enemy then
				for _, bp in ipairs(enemy:GetDescendants()) do
					if bp:IsA("BasePart") then
						bp.Anchored = false
						bp.CanCollide = (bp == enemy.PrimaryPart) -- HRP only
						bp.AssemblyLinearVelocity  = Vector3.zero
						bp.AssemblyAngularVelocity = Vector3.zero
						bp.CollisionGroup = "Default"
					end
				end

				local hum = enemy:FindFirstChildOfClass("Humanoid")
				if hum then
					-- keep as-is; factory already scaled
					hum.MaxHealth = math.max(1, hum.MaxHealth)
					hum.Health    = hum.MaxHealth
					enemy:SetAttribute("BaseDamage", math.max(1, enemy:GetAttribute("BaseDamage") or 10))
				end

				if not CollectionService:HasTag(enemy, "Enemy") then
					CollectionService:AddTag(enemy, "Enemy")
				end

				attachAntiSink(enemy, groundY)

				task.delay(ENEMY_TTL_SEC, function()
					if enemy and enemy.Parent then enemy:Destroy() end
				end)
			end
		end
	end
end

local function rewardAndAdvance(plot)
	local waveIdx = plot:GetAttribute("CurrentWave") or 1
	local W = Waves.get(waveIdx)
	local plr = plotToPlayer[plot]
	if plr and plr:FindFirstChild("leaderstats") and plr.leaderstats:FindFirstChild("Money") then
		plr.leaderstats.Money.Value += W.rewardMoney
	end
	plot:SetAttribute("Seeds", (plot:GetAttribute("Seeds") or 0) + W.rewardSeeds)
	plot:SetAttribute("CurrentWave", waveIdx + 1)
end

local function cleanupLeftovers(plot)
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
		if m:GetAttribute("OwnerUserId") == ownerId and m.Parent then m:Destroy() end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name == "Hero" and m.Parent ~= plot then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then m:Destroy() end
		end
	end
end

local function spawnConfettiAt(plot)
	local anchor = getBannerAnchorPart(plot) or getAnchor(plot, PORTAL_ANCHOR) or plot.PrimaryPart
	if not (anchor and anchor:IsA("BasePart")) then return end

	local p = Instance.new("Part")
	p.Name = "VictoryConfetti"
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.Size = Vector3.new(1,1,1)
	p.CFrame = anchor.CFrame + Vector3.new(0, 6, 0)
	p.Parent = plot

	local emitter = Instance.new("ParticleEmitter")
	emitter.Parent = p
	emitter.Texture = "rbxassetid://241594419"
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(15, 24)
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(60, 180)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255,  80, 80)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB( 80, 180, 90)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB( 80, 120,255)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 210, 70)),
	}
	emitter.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0.0, 0.35),
		NumberSequenceKeypoint.new(1.0, 0.35),
	}

	emitter:Emit(180)
	task.delay(2.0, function() if p then p:Destroy() end end)
end

pinFrozenHeroToIdleGround = function(plot)
	local hero = getHero(plot); if not hero then return end
	local anchor = findHeroAnchor(plot) or plot.PrimaryPart
	if not (anchor and anchor:IsA("BasePart")) then return end

	-- top surface of the anchor
	local topY = anchor.Position.Y + (anchor.Size.Y * 0.5)

	-- put FEET on that surface: topY + HipHeight + HRP half-height
	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
	if not hrp then return end

	local hip = (hum and hum.HipHeight) or 2
	if hip < 0.5 then hip = 2 end

	local targetY = topY + hip + (hrp.Size.Y * 0.5)
	local deltaY  = targetY - hrp.Position.Y

	if math.abs(deltaY) > 1e-4 then
		hero:PivotTo(hero:GetPivot() + Vector3.new(0, deltaY, 0))
	end
end

local function runFightLoop(plot, portal, owner, opts)
	local autoChain       = plot:GetAttribute("AutoChain")
	local wavesThisRun    = 0
	local hero            = ensureHero(plot, owner.UserId)
	local hum             = hero and hero:FindFirstChildOfClass("Humanoid")
	local plr             = plotToPlayer[plot]
	local preSpawned      = (type(opts)=="table" and opts.preSpawned) or false

	if hum then
		hum.BreakJointsOnDeath = false
		if hum.Health <= 0 then hum.Health = hum.MaxHealth end
	end

	local function cleanupLeftovers_local()
		local ownerId = plot:GetAttribute("OwnerUserId") or 0
		for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
			if m:GetAttribute("OwnerUserId") == ownerId and m.Parent then m:Destroy() end
		end
	end

	while true do
		wavesThisRun += 1
		if wavesThisRun > CHAIN_HARD_LIMIT then break end

		if plr then
			local waveIdx = plot:GetAttribute("CurrentWave") or 1
			RE_WaveText:FireClient(plr, {kind="wave", wave=waveIdx})
		end

		if not preSpawned then
			-- make sure the hero can move again for the new wave
			setModelFrozen(hero, false)           -- <— critical (restores collisions / Animator)
			hero:SetAttribute("BarsVisible", 1)   -- <— show HP bar again
			setCombatLock(plot, false)            -- <— allow AI to act

			teleportHeroTo(plot, ARENA_HERO_SPAWN)
			cleanupLeftovers_local()
			spawnWave(plot, portal)
		else
			preSpawned = false
		end

		local startWave = plot:GetAttribute("CurrentWave") or 1
		local t0 = time()
		while enemiesAliveForPlot(plot) > 0 and (time() - t0) < ENEMY_TTL_SEC do
			if hum and hum.Health <= 0 then
				if plr then RE_WaveText:FireClient(plr, {kind="result", result="Defeat", wave=startWave}) end
				task.wait(BANNER_HOLD_SEC)
				local cpStart = ((startWave - 1) // WAVE_CHECKPOINT_INTERVAL) * WAVE_CHECKPOINT_INTERVAL + 1
				if cpStart < 1 then cpStart = 1 end
				plot:SetAttribute("CurrentWave", cpStart)
				teleportHeroTo(plot, HERO_IDLE_ANCHOR, {fullHeal = true})
				cleanupLeftovers_local()
				freezeHeroAtIdle(plot)
				task.defer(pinFrozenHeroToIdleGround, plot)
				return
			end
			task.wait(CHECK_PERIOD)
		end

		rewardAndAdvance(plot)
		if plr then RE_WaveText:FireClient(plr, {kind="result", result="Victory", wave=startWave}) end
		setCombatLock(plot, true)  -- <— block AI/casts during banner
		
		task.wait(BANNER_HOLD_SEC)

		-- after victory, before teleporting back to idle
		if hum and hum.Health > 0 then
			local target = math.floor(hum.MaxHealth * HEAL_BETWEEN_WAVES + 0.5)
			if hum.Health < target then
				local delta = target - hum.Health
				hum.Health = target
				local hrp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
				if hrp then
					local DamageNumbers = require(ReplicatedStorage.Modules.DamageNumbers)
					DamageNumbers.pop(hrp, "+"..delta, Color3.fromRGB(120,255,140))
				end
			end
		end
		setCombatLock(plot, true)  -- NEW: gate AI during between-wave idle
		teleportHeroTo(plot, HERO_IDLE_ANCHOR)
		freezeHeroAtIdle(plot)
		task.defer(pinFrozenHeroToIdleGround, plot)
		cleanupLeftovers_local()

		if not autoChain then break end
		task.wait(BETWEEN_WAVES_DELAY)
	end
end

-- === Portal prompt (legacy stubs; we use ArenaTotem now) ===
local function createPortalPrompt(plot, owner) return false end
local function clearPortalPrompt(plot) end

-- === Totem countdown (owner clicks the Gem) ===
local function startWaveCountdown(plot, portal, owner)
	local totem = findTotem(plot); if not (totem and totem.gem) then return end

	-- lock meta-state (brains may read this), but we do NOT freeze anything anymore
	setCombatLock(plot, true)

	local waveIdx = plot:GetAttribute("CurrentWave") or 1

	-- 3 / 2 / 1 (pure numbers on the board)
	if owner and RE_WaveText then RE_WaveText:FireClient(owner, {kind="countdown", n=3, wave=waveIdx}) end
	playAt(totem.gem, TOTEM_SFX.count3, 0.9);  pulseGem(totem);  task.wait(1.0)
	if owner and RE_WaveText then RE_WaveText:FireClient(owner, {kind="countdown", n=2, wave=waveIdx}) end
	playAt(totem.gem, TOTEM_SFX.count2, 0.95); pulseGem(totem);  task.wait(1.0)
	if owner and RE_WaveText then RE_WaveText:FireClient(owner, {kind="countdown", n=1, wave=waveIdx}) end
	playAt(totem.gem, TOTEM_SFX.count1, 1.0);  pulseGem(totem);  task.wait(1.0)

	-- GO — now teleport hero in, announce wave, and spawn enemies
	if owner and RE_WaveText then RE_WaveText:FireClient(owner, {kind="countdown", n=0, wave=waveIdx}) end
	burstRays(totem, 36); playAt(totem.gem, TOTEM_SFX.go, 1.0)

	setModelFrozen(ensureHero(plot, owner.UserId), false)
	local h = ensureHero(plot, owner.UserId)
	pcall(function() require(script.Parent.RojoServer.Modules.HeroBrain).attach(h) end)
	h:SetAttribute("BarsVisible", 1)
	setModelFrozen(h, false)
	teleportHeroTo(plot, ARENA_HERO_SPAWN)
	local h = ensureHero(plot, owner.UserId)
	if h then h:SetAttribute("BarsVisible", 1) end   -- NEW: show bars
	setCombatLock(plot, false)                       -- NEW: unlock AI for the wave
	if owner and RE_WaveText then RE_WaveText:FireClient(owner, {kind="wave", wave=waveIdx}) end
	spawnWave(plot, portal)
	setCombatLock(plot, false)

	runFightLoop(plot, portal, owner, { preSpawned = true })
end

-- === Totem countdown (owner clicks the Gem or presses E) ===
local function createTotemPrompt(plot, owner)
	local totem = findTotem(plot)
	if not (totem and totem.gem and totem.gem:IsA("BasePart")) then
		warn(("[Totem] Not found on %s"):format(plot.Name))
		return false
	end

	for _, d in ipairs(totem.model:GetDescendants()) do
		if d:IsA("ClickDetector") or d:IsA("ProximityPrompt") then d:Destroy() end
	end

	local pp = Instance.new("ProximityPrompt")
	pp.Name = "StartWavePrompt_Totem"
	pp.ActionText = "Start Wave"
	pp.ObjectText = "Arena Totem"
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 18
	pp.Parent = totem.gem

	local function begin(plr)
		if plr ~= owner or fightBusy[plot] then return end
		local now = time()
		if (now - (lastTriggered[plot] or 0)) < FIGHT_COOLDOWN_SEC then return end
		lastTriggered[plot] = now

		fightBusy[plot] = true
		local portal = getAnchor(plot, PORTAL_ANCHOR) or plot.PrimaryPart or totem.gem
		startWaveCountdown(plot, portal, owner)
		cleanupLeftovers(plot)
		fightBusy[plot] = false
	end

	pp.Triggered:Connect(begin)

	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 18
	cd.Parent = totem.gem
	cd.MouseClick:Connect(begin)

	print(("[Totem] Ready on %s (Gem=%s)"):format(plot.Name, totem.gem:GetFullName()))
	return true
end

-- === Player flow / claim ===
local function teleportPlayerToGate(player, plot)
	local spawn = getAnchor(plot, SPAWN_ANCHOR) or plot.PrimaryPart; if not spawn then return end
	local char = player.Character or player.CharacterAdded:Wait(); if not char then return end
	local cf = spawn.CFrame; local forward = cf.LookVector; local pos = cf.Position + forward*2 + Vector3.new(0,3,0)
	local portal = getAnchor(plot, PORTAL_ANCHOR); local lookAt = (portal and portal.Position) or (pos + forward*8)
	char:PivotTo(CFrame.lookAt(pos, lookAt))
end

local function claimPlot(plot, player)
	ensureAttrs(plot)
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("CurrentWave", plot:GetAttribute("CurrentWave") or 1)

	playerToPlot[player] = plot; plotToPlayer[plot] = player
	setVacantVisual(plot, false); setSignpost(plot, player)
	local hero = ensureHero(plot, player.UserId); if not hero then warn("No hero in plot", plot.Name) end
	teleportHeroTo(plot, HERO_IDLE_ANCHOR, {fullHeal=true})
	freezeHeroAtIdle(plot)
	task.defer(pinFrozenHeroToIdleGround, plot)
	if not createTotemPrompt(plot, player) then
		createPortalPrompt(plot, player)
	end

	teleportPlayerToGate(player, plot)
	print(("[PlotService] Claimed %s for %s"):format(plot.Name, player.Name))
end

local function releasePlot(plot)
	if not plot then return end
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
		if m:GetAttribute("OwnerUserId") == ownerId and m.Parent then m:Destroy() end
	end
	plot:SetAttribute("OwnerUserId", 0)
	setVacantVisual(plot, true); clearPortalPrompt(plot); setSignpost(plot, nil); destroyHero(plot)
	local p = plotToPlayer[plot]; if p then playerToPlot[p] = nil end
	plotToPlayer[plot] = nil; fightBusy[plot] = nil; lastTriggered[plot] = nil
end

local function findFreePlot()
	for _, plot in ipairs(getPlotsSorted()) do
		ensureAttrs(plot)
		if (plot:GetAttribute("OwnerUserId") or 0) == 0 then return plot end
	end
end

local function onPlayerAdded(p)
	p.CharacterAdded:Wait()
	local plot = findFreePlot()
	if plot then claimPlot(plot, p) else warn("[PlotService] No free plots for " .. p.Name) end
end

local function onPlayerRemoving(p)
	local plot = playerToPlot[p]; playerToPlot[p] = nil
	if plot and plotToPlayer[plot] == p then releasePlot(plot) end
end

-- Boot
for _, plot in ipairs(getPlotsSorted()) do ensureAttrs(plot); releasePlot(plot) end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
