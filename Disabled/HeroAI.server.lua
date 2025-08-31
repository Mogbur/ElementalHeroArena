-- ServerScriptService/HeroAI.server.lua
-- (unchanged except for comments) – Walk to nearest enemy *in my plot*, basic melee,
-- auto-cast skills with per-skill CDs + global CD.

-- ==== singleton guard (place at line 1) ====
if _G.__HERO_AI_RUNNING then
	warn("[HeroAI] Duplicate copy detected at", script:GetFullName())
	return
end
_G.__HERO_AI_RUNNING = true
print("[HeroAI] started once from", script:GetFullName())
-- ===========================================

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local PhysicsService       = game:GetService("PhysicsService")
local CollectionService    = game:GetService("CollectionService")
local ServerScriptService  = game:GetService("ServerScriptService")
local HttpService          = game:GetService("HttpService")

local PLOTS = workspace:FindFirstChild("Plots") or workspace
local PLOT_NAME_PATTERN = "^BasePlot%d+$"

local SkillConfig = require(ReplicatedStorage.Modules.SkillConfig)
local Tuning      = require(ReplicatedStorage.Modules.SkillTuning)

local RS      = ReplicatedStorage
local Remotes = RS:WaitForChild("Remotes")
local RE_DMG  = Remotes:WaitForChild("DamageNumbers")

-- Optional Combat module
local okCombat, Combat = pcall(function()
	return require(ServerScriptService.RojoServer.Modules.Combat)
end)
if not okCombat then Combat = nil end

-- NEW/CHANGED: make sure the “Hero” collision group exists and collides with Default.
local function ensureCollisionGroups()
	pcall(function() PhysicsService:RegisterCollisionGroup("Hero") end)
	-- Let heroes stand on normal parts/terrain. (Set Hero-vs-Hero to taste.)
	PhysicsService:CollisionGroupSetCollidable("Hero","Default", true)
	PhysicsService:CollisionGroupSetCollidable("Hero","Hero",   false)
end
ensureCollisionGroups()

-- (rest of file exactly as you provided)
-- ..........................
-- (No changes to logic here to keep your behavior intact)
-- <keep your entire original HeroAI.server.lua content from your paste>

-- ---------- helpers ----------
local function isPlot(x) return x:IsA("Model") and x.Name:match(PLOT_NAME_PATTERN) end

local function getHero(plot)
	local h = plot:FindFirstChild("Hero", true)
	if h and h:IsA("Model") and h:FindFirstChildOfClass("Humanoid") and h:FindFirstChild("HumanoidRootPart") then
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

local function rootOf(model)
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("EnemyBlock")
		or model:FindFirstChildWhichIsA("BasePart")
end

local function humAlive(model)
	local h = model and model:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then return h end
end

local function canon(id)
	id = tostring(id or ""):lower()
	if id == "aquaburst" or id == "watershield" then return "aquabarrier" end
	if id == "quake" or id == "pulse"       then return "quakepulse"  end
	if id == "fire"  or id == "bolt"        then return "firebolt"    end
	return id
end

-- plot ownership checks (folder/tag/attr)
local function belongsToPlot(model, plot)
	if not (model and plot) then return false end
	local ownerId = plot:GetAttribute("OwnerUserId")

	local a = model
	while a and a ~= workspace and not isPlot(a) do a = a.Parent end
	if a == plot then return true end

	if (model:GetAttribute("OwnerUserId") or 0) == (ownerId or -1) then
		return true
	end

	local arena  = plot:FindFirstChild("Arena")
	local folder = arena and arena:FindFirstChild("Enemies")
	if folder and model:IsDescendantOf(folder) then
		return true
	end
	return false
end

local function enemiesInPlot(plot)
	local list, seen = {}, {}

	local arena  = plot:FindFirstChild("Arena")
	local folder = arena and arena:FindFirstChild("Enemies")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and (m:GetAttribute("IsEnemy") or m.Name=="Enemy" or m:FindFirstChildOfClass("Humanoid")) then
				seen[m] = true; table.insert(list, m)
			end
		end
	end

	for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
		if m.Parent and m:IsA("Model") and not seen[m] and belongsToPlot(m, plot) then
			seen[m] = true; table.insert(list, m)
		end
	end

	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and not seen[d] and (d:GetAttribute("IsEnemy") or d.Name=="Enemy") and belongsToPlot(d, plot) then
			seen[d] = true; table.insert(list, d)
		end
	end

	return list
end

local function aliveEnemyCount(plot)
	local c = 0
	for _, m in ipairs(enemiesInPlot(plot)) do
		if humAlive(m) then c += 1 end
	end
	return c
end

-- nearest living enemy model + distance
local function nearestEnemyForPlot(plot, fromPos, maxDist)
	local best, bestD
	for _, m in ipairs(enemiesInPlot(plot)) do
		local r = rootOf(m)
		local hum = humAlive(m)
		if r and hum then
			local d = (r.Position - fromPos).Magnitude
			if (not maxDist or d <= maxDist) and (not bestD or d < bestD) then
				best, bestD = m, d
			end
		end
	end
	return best, bestD
end

-- ----- tiny VFX -----
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

-- damage + numbers
local function safeDamage(owner, targetModelOrPart, amount, elem, kind)
	if Combat and Combat.ApplyDamage then
		Combat.ApplyDamage(owner, targetModelOrPart, amount, elem)
	else
		local m = targetModelOrPart:IsA("BasePart") and targetModelOrPart.Parent or targetModelOrPart
		local hum = humAlive(m)
		if hum then hum:TakeDamage(amount) end
	end

	local m = targetModelOrPart:IsA("BasePart") and targetModelOrPart.Parent or targetModelOrPart
	local r = rootOf(m)
	if r then
		RE_DMG:FireAllClients({
			amount = math.floor((amount or 0) + 0.5),
			pos    = r.Position,
			color  = Color3.fromRGB(255,235,130),
			kind   = kind or "skill",
		})
	end
end

-- equipment order
local function equippedSkillsFor(owner)
	if not owner then return {} end
	local list, seen = {}, {}
	local function add(raw)
		local c = canon(raw)
		if c and not seen[c] then seen[c] = true; table.insert(list, c) end
	end
	add(owner:GetAttribute("Equip_Primary"))
	add(owner:GetAttribute("Equip_Utility"))
	add(owner:GetAttribute("Equip_Slot3"))
	return list
end

-- stats
local function statsFire(lv)
	local s = SkillConfig.firebolt.stats(lv)
	return { dmg = s.damage or 20, range = s.range or (Tuning.FIRE_RANGE or 46), cd = s.cooldown or (Tuning.CD and Tuning.CD.firebolt) or 6 }
end
local function statsQuake(lv)
	local s = SkillConfig.quakepulse.stats(lv)
	return { dmg = s.damage or 50, radius = s.radius or (Tuning.QUAKE_RANGE or 10), cd = s.cooldown or (Tuning.CD and Tuning.CD.quakepulse) or 10 }
end
local function statsAqua(lv)
	local s = SkillConfig.aquabarrier.stats(lv)
	return {
		dotTotal = s.damage or 30, duration = s.duration or (Tuning.AQUA_DURATION or 6),
		radius = s.radius or 10, cd = s.cooldown or (Tuning.CD and Tuning.CD.aquabarrier) or 10,
		triggerRange = s.triggerRange or 12, triggerEnemyCount = s.triggerEnemyCount or 2,
		radiusVisual = s.radiusVisual or 10, shield = s.shield or 0
	}
end

-- casts (return true iff actually fired)
local function castFirebolt(owner, hero, targetModel)
	local lvl = tonumber(owner:GetAttribute("Skill_firebolt")) or tonumber(owner:GetAttribute("Skill_Firebolt")) or 0
	if lvl <= 0 then return false end
	local s = statsFire(lvl)

	local hrp = hero:FindFirstChild("HumanoidRootPart"); if not hrp then return false end
	local tRoot = rootOf(targetModel); if not tRoot then return false end
	if (tRoot.Position - hrp.Position).Magnitude > s.range then return false end

	quickBeam(hrp.Position + Vector3.new(0,2.8,0), tRoot.Position + Vector3.new(0,2.0,0), Color3.fromRGB(255,120,60))
	safeDamage(owner, targetModel, s.dmg, "Fire", "skill")
	hero:SetAttribute("CastTick", "firebolt")
	return true
end

local function castQuakePulse(owner, hero, plot)
	local lvl = tonumber(owner:GetAttribute("Skill_quakepulse")) or tonumber(owner:GetAttribute("Skill_QuakePulse")) or 0
	if lvl <= 0 then return false end
	local s = statsQuake(lvl)

	local hrp = hero:FindFirstChild("HumanoidRootPart"); if not hrp then return false end
	local pos = hrp.Position

	local count = 0
	for _, m in ipairs(enemiesInPlot(plot)) do
		local r, hum = rootOf(m), humAlive(m)
		if r and hum and (r.Position - pos).Magnitude <= s.radius then
			count += 1; if count >= 2 then break end
		end
	end
	if count < 2 then return false end

	for _, m in ipairs(enemiesInPlot(plot)) do
		local r, hum = rootOf(m), humAlive(m)
		if r and hum and (r.Position - pos).Magnitude <= s.radius then
			safeDamage(owner, m, s.dmg, "Earth", "skill")
		end
	end

	-- quick ring
	local ring = Instance.new("Part")
	ring.Anchored=true; ring.CanCollide=false; ring.Material=Enum.Material.Neon
	ring.Color=Color3.fromRGB(200,180,120)
	ring.Size=Vector3.new(s.radius*2, 0.2, s.radius*2)
	ring.CFrame=CFrame.new(pos + Vector3.new(0,0.2,0))
	local m = Instance.new("CylinderMesh", ring); m.Scale = Vector3.new(1,0.05,1)
	ring.Parent=workspace; task.delay(0.25,function() ring:Destroy() end)

	hero:SetAttribute("CastTick", "quakepulse")
	return true
end

local function castAquaBarrier(owner, hero, plot)
	local lvl = tonumber(owner:GetAttribute("Skill_aquabarrier")) or tonumber(owner:GetAttribute("Skill_Watershield")) or 0
	if lvl <= 0 then return false end

	local s = statsAqua(lvl)
	-- fallbacks / tuning
	local HP_THRESHOLD = Tuning.AQUA_HP_THRESHOLD or 0.75
	local DURATION     = s.duration or (Tuning.AQUA_DURATION or 6)
	local DOT_TOTAL    = s.dotTotal or 30
	local RADIUS_DMG   = s.radius or 10
	local RADIUS_NEAR  = s.triggerRange or 12
	local NEED_ENEMIES = s.triggerEnemyCount or 1
	local SHIELD_HP    = math.max(0, s.shield or 0)
	local HOT_TOTAL    = (lvl >= 5) and (s.hotTotal or 40) or 0   -- heal from lv5+

	local hrp = hero:FindFirstChild("HumanoidRootPart"); if not hrp then return false end
	local hum = hero:FindFirstChildOfClass("Humanoid");   if not hum then return false end

	-- 0) don’t re-cast if an active shield exists
	if (hero:GetAttribute("ShieldHP") or 0) > 0 and (hero:GetAttribute("ShieldExpireAt") or 0) > os.clock() then
		return false
	end

	-- 1) low-ish HP gate
	if hum.MaxHealth > 0 then
		local hpFrac = hum.Health / hum.MaxHealth
		if hpFrac > HP_THRESHOLD then return false end
	end

	-- 2) threat gate (enemies near within trigger range)
	local pos, near = hrp.Position, 0
	for _, m in ipairs(enemiesInPlot(plot)) do
		local r, h = rootOf(m), humAlive(m)
		if r and h and (r.Position - pos).Magnitude <= RADIUS_NEAR then
			near += 1; if near >= NEED_ENEMIES then break end
		end
	end
	if near < NEED_ENEMIES then return false end

	-- 3) VISUAL bubble (ForceField + faint sphere), removed on expire/pop
	local ff = Instance.new("ForceField")
	ff.Name = "AquaShield"
	ff.Visible = true
	ff.Parent = hero

	local bubble = Instance.new("Part")
	bubble.Name = "AquaBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(80, 140, 255)
	bubble.Transparency = 0.25
	bubble.CanCollide = false
	bubble.Anchored = false
	bubble.Size = Vector3.new((s.radiusVisual or 10), (s.radiusVisual or 10), (s.radiusVisual or 10))
	bubble.CFrame = hrp.CFrame
	bubble.Parent = hero
	local weld = Instance.new("WeldConstraint", bubble)
	weld.Part0, weld.Part1 = bubble, hrp

	-- 4) Arm shield + expiry
	hero:SetAttribute("ShieldHP", SHIELD_HP)
	hero:SetAttribute("ShieldExpireAt", os.clock() + DURATION)
	hero:SetAttribute("ShieldOwner", owner.UserId or 0)

	-- 5) DoT aura (continues even if shield breaks early)
	local dotTicks = 5
	local dotPer   = math.max(1, math.floor(DOT_TOTAL / dotTicks + 0.5))
	task.spawn(function()
		for _ = 1, dotTicks do
			for _, m in ipairs(enemiesInPlot(plot)) do
				local r, h = rootOf(m), humAlive(m)
				if r and h and (r.Position - pos).Magnitude <= RADIUS_DMG then
					safeDamage(owner, m, dotPer, "Water", "skill")
				end
			end
			task.wait(1.0)
		end
	end)

	-- 6) HoT (lvl >= 5), independent of shield/bubble life
	if HOT_TOTAL > 0 then
		local hotTicks = 5
		local hotPer   = math.max(1, math.floor(HOT_TOTAL / hotTicks + 0.5))
		task.spawn(function()
			for _ = 1, hotTicks do
				if hum and hum.Health > 0 then
					hum.Health = math.min(hum.MaxHealth, hum.Health + hotPer)
				end
				task.wait(1.0)
			end
		end)
	end

	-- 7) Auto-cleanup bubble on time or when shield reaches 0 (Combat will zero it)
	task.spawn(function()
		while hero and hero.Parent do
			local alive = (os.clock() < (hero:GetAttribute("ShieldExpireAt") or 0))
			            and ((hero:GetAttribute("ShieldHP") or 0) > 0)
			if not alive then break end
			task.wait(0.1)
		end
		if hero then
			hero:SetAttribute("ShieldHP", 0)
			hero:SetAttribute("ShieldExpireAt", 0)
		end
		if ff then ff:Destroy() end
		if bubble then bubble:Destroy() end
	end)

	hero:SetAttribute("CastTick", "aquabarrier")
	return true
end

local function cooldownFor(id)
	local CD = Tuning.CD or {}
	if id == "firebolt"    then return CD.firebolt    or 6
	elseif id == "quakepulse"  then return CD.quakepulse  or 10
	elseif id == "aquabarrier" then return CD.aquabarrier or 10 end
	return 6
end

-- ========== AI loop ==========
local STATE = {} -- [hero] = { lastBasic, skillNext={id=time}, globalNext, initStaggered, lastCastAt, lastGroundFix }
local BASIC_DMG   = 18
local BASIC_RANGE = 6
local BASIC_CD    = 1.2
local GCD         = Tuning.GLOBAL_CD or 3.0
local ANTI_SPAM   = 0.20

-- NEW/CHANGED: atomic controller claim so only one brain drives each Hero.
local CLAIM_TOKEN = HttpService:GenerateGUID(false)
local function haveControl(hero)
	local cur = hero:GetAttribute("AIController")
	if cur == CLAIM_TOKEN then return true end
	if cur == nil then
		hero:SetAttribute("AIController", CLAIM_TOKEN)
		if hero:GetAttribute("AIController") == CLAIM_TOKEN then return true end
	end
	return false
end

-- NEW/CHANGED: robust ground clamp (collidable floor only, throttled).
local RAY_PARAMS = RaycastParams.new()
RAY_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
local function findFloorY(hrp, exclude)
	if not hrp then return nil end
	RAY_PARAMS.FilterDescendantsInstances = exclude or {}
	local origin = hrp.Position + Vector3.new(0, 5, 0)
	for _=1,4 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -40, 0), RAY_PARAMS)
		if not hit then return nil end
		if hit.Instance and hit.Instance.CanCollide then
			return hit.Position.Y
		else
			origin = hit.Position - Vector3.new(0, 0.05, 0)
		end
	end
	return nil
end
local function clampToGround(hero, hum, hrp, st)
	if not (hero and hum and hrp) then return end
	local now = os.clock()
	if (now - (st.lastGroundFix or 0)) < 0.25 then return end -- throttle
	st.lastGroundFix = now

	local yFloor = findFloorY(hrp, {hero})
	if not yFloor then return end

	-- keep feet on floor
	local targetY = yFloor + math.max(hum.HipHeight, 1.6) + (hrp.Size.Y * 0.5)
	local pos = hrp.Position
	if math.abs(pos.Y - targetY) > 0.25 then
		local cx, cy, cz,
		      r00,r01,r02, r10,r11,r12, r20,r21,r22 = hrp.CFrame:GetComponents()
		hrp.CFrame = CFrame.new(cx, targetY, cz, r00,r01,r02, r10,r11,r12, r20,r21,r22)
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end
end

local function stepHero(plot, hero)
	if not haveControl(hero) then return end -- NEW/CHANGED

	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then return end

	-- stop & soft reset when no living enemies
	if aliveEnemyCount(plot) == 0 then
		hum:Move(Vector3.new())
		local st = STATE[hero]
		if st then
			st.initStaggered = false
			st.skillNext = {}
			st.globalNext = 0
			st.lastCastAt = 0
			st.lastBasic = time()
		end
		return
	end

	-- ensure movable + *colliding* with floor
	for _, bp in ipairs(hero:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			PhysicsService:SetPartCollisionGroup(bp, "Hero")
		end
	end
	hrp:SetNetworkOwner(nil)
	hum.WalkSpeed = 12
	if hum.HipHeight < 1.8 then hum.HipHeight = 2.0 end

	local st = STATE[hero]; if not st then
		st = { lastBasic = 0, skillNext = {}, globalNext = 0, initStaggered = false, lastCastAt = 0, lastGroundFix = 0 }
		STATE[hero] = st
	end

	-- keep him planted (fixes sinking at idle spot)
	clampToGround(hero, hum, hrp, st) -- NEW/CHANGED

	local owner = getOwner(plot)

	-- target
	local targetModel, dist = nearestEnemyForPlot(plot, hrp.Position, 200)
	if not targetModel then hum:Move(Vector3.new()); return end
	local tRoot = rootOf(targetModel); if not tRoot then return end

	-- face & move
	hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(tRoot.Position.X, hrp.Position.Y, tRoot.Position.Z))
	if dist > BASIC_RANGE * 0.9 then
		hum:MoveTo(tRoot.Position)
	else
		hum:Move(Vector3.new())
	end

	-- basic melee
	if time() - (st.lastBasic or 0) >= BASIC_CD and dist <= BASIC_RANGE + 0.3 then
		safeDamage(owner, targetModel, BASIC_DMG, "Neutral", "melee")
		hero:SetAttribute("MeleeTick", os.clock())
		st.lastBasic = time()
	end

	-- === skill scheduler ===
	if not owner then return end
	local slots = equippedSkillsFor(owner)

	-- initial staggering at combat start (0s, +3s, +6s...)
	if not st.initStaggered then
		local now0 = os.clock() + 0.03
		for i, id in ipairs(slots) do
			st.skillNext[id] = now0 + (i-1) * GCD
		end
		st.globalNext = now0
		st.initStaggered = true
	end

	local now = os.clock()
	if now < (st.globalNext or 0) then return end
	if now - (st.lastCastAt or 0) < ANTI_SPAM then return end

	for _, id in ipairs(slots) do
		if now >= (st.skillNext[id] or 0) then
			local casted = false
			if id == "firebolt"        then casted = castFirebolt(owner, hero, targetModel)
			elseif id == "quakepulse"  then casted = castQuakePulse(owner, hero, plot)
			elseif id == "aquabarrier" then casted = castAquaBarrier(owner, hero, plot)
			end
			if casted then
				st.globalNext    = now + GCD
				st.skillNext[id] = now + cooldownFor(id)
				st.lastCastAt    = now
				break -- one per GCD
			end
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
