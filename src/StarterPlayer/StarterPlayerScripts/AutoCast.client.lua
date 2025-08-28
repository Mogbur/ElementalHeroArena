-- AutoCast.client.lua  (equip-aware: sends only your equipped skill)
-- Priority inside the chosen skill: Quake> (panic window) > Fire > Aqua rules

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local RE_Cast = Remotes:WaitForChild("CastSkillRequest")

-- ---- tuning (from SkillTuning if present) ----
local Tmod = RS:FindFirstChild("SkillTuning")
local T    = (Tmod and require(Tmod)) or {}
local C    = (T.CLIENT or T.Client) or {}

local DEBUG              = false
local TICK               = C.TICK               or 0.10
local QUAKE_RADIUS       = C.QUAKE_RADIUS       or T.QUAKE_RANGE or 10
local QUAKE_MIN_ENEMIES  = C.QUAKE_MIN_ENEMIES  or 2
local HIT_TRIGGER_WINDOW = C.HIT_TRIGGER_WINDOW or 1.0
local FIRE_RANGE         = C.FIRE_RANGE         or T.FIRE_RANGE  or 46
local AQUA_HP_THRESHOLD  = C.AQUA_HP_THRESHOLD  or 0.75
local LOCAL_SEND_GUARD   = C.SEND_GUARD         or 0.20

if DEBUG then
	print(("[AutoCast] rQ=%d min=%d | rF=%d | AquaHP=%.2f"):format(QUAKE_RADIUS, QUAKE_MIN_ENEMIES, FIRE_RANGE, AQUA_HP_THRESHOLD))
end


-- ---- utils ----
local lp = Players.LocalPlayer
local function hrpOf(model) return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) end
local function humOf(model) return model and model:FindFirstChildOfClass("Humanoid") end
local function dist(a,b) return (a - b).Magnitude end
local function okHum(h) return h and h.Health > 0 end

-- canonicalize ids
local function canon(id)
	id = tostring(id or ""):lower()
	if id == "aquaburst" or id == "watershield" then return "aquabarrier" end
	if id == "quake" then return "quakepulse" end
	if id == "fire" or id == "bolt" then return "firebolt" end
	return id
end

-- read owned level (mirrors your server attrs; includes legacy keys)
local function ownedLevel(id)
	id = canon(id)
	local v = lp:GetAttribute("Skill_"..id)
	if v == nil then
		if id == "aquabarrier" then v = lp:GetAttribute("Skill_aquaburst") end
		if id == "quakepulse"  then v = lp:GetAttribute("Skill_quake")     end
	end
	return tonumber(v) or 0
end

-- track equipped (primary + utility if you use it)
local EQUIPPED = {}
local function refreshEquipped()
	EQUIPPED = {}
	local p = canon(lp:GetAttribute("Equip_Primary"))
	local u = canon(lp:GetAttribute("Equip_Utility"))
	if p and p ~= "" then EQUIPPED[p] = true end
	if u and u ~= "" then EQUIPPED[u] = true end
end
lp:GetAttributeChangedSignal("Equip_Primary"):Connect(refreshEquipped)
lp:GetAttributeChangedSignal("Equip_Utility"):Connect(refreshEquipped)
task.defer(refreshEquipped)

-- single gate
local function allowed(id)
	id = canon(id)
	return EQUIPPED[id] and ownedLevel(id) > 0
end

local ALIAS = {
	quake = "quakepulse", quakepulse = "quakepulse",
	aquaburst = "aquabarrier", aquabarrier = "aquabarrier", watershield = "aquabarrier",
	fire = "firebolt", bolt = "firebolt", firebolt = "firebolt",
}
local function norm(id)
	return ALIAS[string.lower(tostring(id or ""))] or ""
end

local function myPlot()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _,m in ipairs(plots:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == lp.UserId then
			return m
		end
	end
	return nil
end

local function plotHero(plot)
	if not plot then return nil end
	local h = plot:FindFirstChild("Hero", true)
	if h and h:IsA("Model") then return h end
end

local function enemiesFolder(plot)
	local arena = plot and plot:FindFirstChild("Arena")
	return arena and arena:FindFirstChild("Enemies")
end

local function workspaceEnemyModels()
	local list = {}
	for _,d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and (d:GetAttribute("IsEnemy") or d.Name == "Enemy") then
			table.insert(list, d)
		end
	end
	return list
end

local function enemiesNear(pos, radius, plot)
	local folder = enemiesFolder(plot)
	local count = 0
	if folder then
		for _,m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				local h, r = humOf(m), hrpOf(m)
				if okHum(h) and r and dist(r.Position, pos) <= radius then
					count += 1
				end
			end
		end
	else
		for _,m in ipairs(workspaceEnemyModels()) do
			local h, r = humOf(m), hrpOf(m)
			if okHum(h) and r and dist(r.Position, pos) <= radius then
				count += 1
			end
		end
	end
	return count
end

-- local throttle so we don’t spam the remote
local lastSend = 0
local function cast(id)
	local now = os.clock()
	if (now - lastSend) < LOCAL_SEND_GUARD then return end
	lastSend = now
	if DEBUG then print("[AutoCast] send", id) end
	RE_Cast:FireServer({ kind = id })
end

-- “panic” window when *hero* gets hit
local recentlyHitUntil = 0
local function markHit() recentlyHitUntil = os.clock() + HIT_TRIGGER_WINDOW end

local equippedNorm = ""
local function readEquipped()
	local raw = lp:GetAttribute("Equip_Primary")
	local n = norm(raw)
	if n ~= equippedNorm then
		equippedNorm = n
		if DEBUG then print("[AutoCast] equipped =", equippedNorm) end
	end
end
lp:GetAttributeChangedSignal("Equip_Primary"):Connect(readEquipped)

-- ---- main loop ----
local function run()
	-- bootstrap on character (keeps loop alive through respawns)
	local char = lp.Character or lp.CharacterAdded:Wait()
	local _playerHum = humOf(char)

	local plot, hero, heroHum, heroHRP

	local function refreshPlot()
		local p = myPlot()
		if p ~= plot then
			plot = p
			if DEBUG then print("[AutoCast] plot ->", plot and plot.Name or "nil") end
		end
	end

	local function refreshHero()
		local h = plotHero(plot)
		if h ~= hero then
			hero = h
			heroHum = humOf(hero)
			heroHRP = hrpOf(hero)
			if DEBUG then print("[AutoCast] hero ->", hero and hero:GetFullName() or "nil") end
			if heroHum then
				local last = heroHum.Health
				heroHum.HealthChanged:Connect(function(n)
					if n < last then markHit() end
					last = n
				end)
			end
		else
			heroHRP = hrpOf(hero) or heroHRP
		end
	end

	while task.wait(TICK) do
		refreshPlot()
		refreshHero()

		-- pause autocast if hero is dead OR plot is combat-locked (defeat/victory banner)
		if (heroHum and heroHum.Health <= 0) or (plot and plot:GetAttribute("CombatLocked")) then
			recentlyHitUntil = 0
			continue
		end

		-- pick a position: hero first, fallback to player
		local pos =
			(heroHRP and heroHRP.Position)
			or (char and hrpOf(char) and hrpOf(char).Position)
		if not pos then
			if DEBUG then print("[AutoCast] waiting for pos...") end
			continue
		end

		local closeCount = enemiesNear(pos, QUAKE_RADIUS, plot)

		-- 1) QuakePulse ASAP (enemy near OR just got hit) — gated by owned+equipped
		if allowed("quakepulse") and (closeCount >= QUAKE_MIN_ENEMIES or os.clock() < recentlyHitUntil) then
			cast("quakepulse")
			recentlyHitUntil = 0
			continue
		end

		-- 2) AquaBarrier when HERO low-ish HP — gated by owned+equipped
		if allowed("aquabarrier")
			and heroHum
			and (heroHum.Health / math.max(1, heroHum.MaxHealth)) <= AQUA_HP_THRESHOLD
			and closeCount >= 1
		then
			cast("aquabarrier")
		end

		-- 3) Firebolt if anything in range — gated by owned+equipped
		if allowed("firebolt") and enemiesNear(pos, FIRE_RANGE, plot) > 0 then
			cast("firebolt")
		end
	end
end

-- boot + reboot on respawn
task.spawn(run)
lp.CharacterAdded:Connect(function() task.spawn(run) end)
