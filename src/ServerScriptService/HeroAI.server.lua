-- HeroAI.server.lua
-- Walk to nearest EnemyBlock in *my plot*, basic melee, auto-cast skills with rules.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local PLOTS = workspace:FindFirstChild("Plots") or workspace
local PLOT_NAME_PATTERN = "^BasePlot%d+$"

local SkillConfig = require(ReplicatedStorage:WaitForChild("SkillConfig"))

-- -------- helpers --------
local function isPlot(x) return x:IsA("Model") and x.Name:match(PLOT_NAME_PATTERN) end
local function getHero(plot)
	local h = plot:FindFirstChild("Hero", true)
	if h and h:IsA("Model") and h:FindFirstChild("Humanoid") and h:FindFirstChild("HumanoidRootPart") then
		return h
	end
end
local function getOwner(plot)
	for _, plr in ipairs(Players:GetPlayers()) do
		if (plot:GetAttribute("OwnerUserId") or 0) == plr.UserId then
			return plr
		end
	end
end

-- nearest enemy **restricted to this plot**
local function nearestEnemyInPlot(plotId, fromPos, maxDist)
	local best, bestD
	for _, p in ipairs(workspace:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "EnemyBlock" and p.Parent and (p:GetAttribute("PlotId") == plotId) then
			local d = (p.Position - fromPos).Magnitude
			if (not maxDist or d <= maxDist) and (not best or d < bestD) then
				best, bestD = p, d
			end
		end
	end
	return best, bestD
end

-- ------- tiny VFX -------
local function quickBeam(a, b, color)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255,120,60)
	local len = (b - a).Magnitude
	part.Size = Vector3.new(0.25, 0.25, math.max(0.5, len))
	part.CFrame = CFrame.new(a, b) * CFrame.new(0,0,-len/2)
	part.Parent = workspace
	task.delay(0.15, function() if part then part:Destroy() end end)
end

-- ------- skills -------
local function castFirebolt(owner, hero, target)
	local lvl = owner:GetAttribute("Skill_Firebolt") or 0
	if lvl <= 0 then return end
	local stats = SkillConfig.Firebolt.stats(lvl)
	if not (hero and target and target.Parent) then return end
	local hrp = hero:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	if (target.Position - hrp.Position).Magnitude > stats.range then return end
	quickBeam(hrp.Position + Vector3.new(0,2,0), target.Position + Vector3.new(0,1,0), Color3.fromRGB(255,120,60))
	require(script.Parent.Combat)(owner, target, stats.damage, "Fire") -- fallback if someone kept old module? (safe)
end

local Combat = require(game:GetService("ServerScriptService"):WaitForChild("Combat"))
local function castQuakePulse(owner, hero)
	local lvl = owner:GetAttribute("Skill_QuakePulse") or 0
	if lvl <= 0 then return end
	local s = SkillConfig.QuakePulse.stats(lvl)
	local hrp = hero:FindFirstChild("HumanoidRootPart"); if not hrp then return end

	-- only if enough enemies in radius
	local count = 0
	for _, p in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, s.radius)) do
		if p.Name == "EnemyBlock" then count += 1 end
	end
	if count < (s.minTargets or 1) then return end

	Combat.ApplyAOE(owner, hrp.Position, s.radius, s.damage, "Earth", s.rootSec)

	local ring = Instance.new("Part")
	ring.Anchored=true; ring.CanCollide=false; ring.Material=Enum.Material.Neon
	ring.Color=Color3.fromRGB(200,180,120)
	ring.Size=Vector3.new(s.radius*2, 0.2, s.radius*2)
	ring.CFrame=CFrame.new(hrp.Position + Vector3.new(0,0.2,0))
	local m = Instance.new("CylinderMesh", ring); m.Scale = Vector3.new(1,0.05,1)
	ring.Parent=workspace; task.delay(0.25,function() ring:Destroy() end)
end

local function castWatershield(owner, hero)
	local lvl = owner:GetAttribute("Skill_Watershield") or 0
	if lvl <= 0 then return end
	local s = SkillConfig.Watershield.stats(lvl)
	local hrp = hero:FindFirstChild("HumanoidRootPart"); if not hrp then return end

	-- threat check
	local count = 0
	for _, p in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, s.triggerRange)) do
		if p.Name == "EnemyBlock" then count += 1 end
	end
	if count < (s.triggerEnemyCount or 2) then return end

	-- quick orb VFX
	local orb = Instance.new("Part"); orb.Shape=Enum.PartType.Ball; orb.Anchored=true; orb.CanCollide=false
	orb.Color=Color3.fromRGB(80,140,255); orb.Material=Enum.Material.ForceField
	orb.Size=Vector3.new(s.radiusVisual, s.radiusVisual, s.radiusVisual)
	orb.CFrame=CFrame.new(hrp.Position)
	orb.Parent=workspace; task.delay(0.4,function() orb:Destroy() end)
end

-- ------- AI loop -------
local STATE = {} -- [hero] = { lastBasic, lastSkill }
local BASIC_DMG = 18
local BASIC_RANGE = 6
local BASIC_CD = 1.2
local BETWEEN_SKILLS = 3.0

local function stepHero(plot, hero)
	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then return end

	-- group & unanchor safety
	for _, bp in ipairs(hero:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			PhysicsService:SetPartCollisionGroup(bp, "Hero")
		end
	end

	hrp:SetNetworkOwner(nil)
	hum.WalkSpeed = 12

	local owner = getOwner(plot)
	local plotId = plot:GetAttribute("PlotId") or plot.Name

	local st = STATE[hero]; if not st then st = {lastBasic = 0, lastSkill = 0}; STATE[hero] = st end

	local target, dist = nearestEnemyInPlot(plotId, hrp.Position, 200)
	if not target then hum:Move(Vector3.new()); return end

	-- face & move
	hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.Position.X, hrp.Position.Y, target.Position.Z))
	if dist > BASIC_RANGE * 0.9 then
		hum:MoveTo(target.Position)
	else
		hum:Move(Vector3.new())
	end

	-- basic hit
	if time() - (st.lastBasic or 0) >= BASIC_CD and dist <= BASIC_RANGE + 0.3 then
		Combat.ApplyDamage(owner, target, BASIC_DMG, "Neutral")
		st.lastBasic = time()
	end

	-- skill pacing
	if time() - (st.lastSkill or 0) >= BETWEEN_SKILLS then
		st.lastSkill = time()
		local primary = owner and owner:GetAttribute("Equip_Primary")
		if primary == "Firebolt" then
			castFirebolt(owner, hero, target)
		elseif primary == "QuakePulse" then
			castQuakePulse(owner, hero)
		end
		local util = owner and owner:GetAttribute("Equip_Utility")
		if util == "Watershield" then
			castWatershield(owner, hero)
		end
	end
end

RunService.Heartbeat:Connect(function()
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if isPlot(plot) then
			local hero = getHero(plot)
			if hero then stepHero(plot, hero) end
		end
	end
end)
