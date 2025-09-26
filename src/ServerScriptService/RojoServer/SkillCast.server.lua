-- ServerScriptService/SkillCast.server.lua
-- Receives CastSkillRequest, finds a target, applies damage, broadcasts VFX + numbers.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local SSS     = game:GetService("ServerScriptService")

-- === robust require for Combat (SSS.RojoServer.Modules, SSS.Modules, or RS.Modules) ===
local function requireCombat()
	-- 1) ServerScriptService/RojoServer/Modules/Combat
	local rojo = SSS:FindFirstChild("RojoServer")
	if rojo then
		local mods = rojo:FindFirstChild("Modules")
		local c = mods and mods:FindFirstChild("Combat")
		if c then return require(c) end
	end
	-- 2) ServerScriptService/Modules/Combat
	local mods2 = SSS:FindFirstChild("Modules")
	local c2 = mods2 and mods2:FindFirstChild("Combat")
	if c2 then return require(c2) end
	-- 3) ReplicatedStorage/Modules/Combat
	local mods3 = RS:FindFirstChild("Modules")
	local c3 = mods3 and mods3:FindFirstChild("Combat")
	if c3 then return require(c3) end

	error("Combat module not found. Expected at:\n" ..
	      " - ServerScriptService/RojoServer/Modules/Combat.lua\n" ..
	      " - ServerScriptService/Modules/Combat.lua\n" ..
	      " - ReplicatedStorage/Modules/Combat.lua")
end
local Combat = requireCombat()
-- ================================================================================

-- ===== remotes (self-ensuring) =====
local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = RS

local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local RE_Cast = ensureRemote("CastSkillRequest")
local RE_VFX  = ensureRemote("SkillVFX")
local RE_DMG  = ensureRemote("DamageNumbers")

-- ===== tuning (safe require with fallback) =====
local DEFAULT = {
	MAX_LEVEL     = 5,
	FIRE_RANGE    = 45,
	QUAKE_RANGE   = 10,
	AQUA_DURATION = 6,
	CD            = { firebolt = 6, aquabarrier = 10, quakepulse = 10 },
	Skills = {
		firebolt    = { hit = {30,40,50,60,75}, range = 45, cd = 6,  dotPctLv5 = 0.45 },
		aquabarrier = { dmg = {22,30,38,48,60}, radius = 10, duration = 6, cd = 10,
		                hotTotalLv5 = 70, hotTicks = 5, selfDoubleHoT = true,
		                dotTotal = {22,30,38,48,60}, dotTicks = 5, dotRadius = 10,
		                shield = {50,65,80,95,110}, },
		quakepulse  = { hit = {45,60,75,90,105}, radius = 10, cd = 10,
		                aftershockPct = 0.5, fracturePct = 0.15, fractureDur = 4.0 },
	},
}

local ok, T = pcall(function()
	return require(RS:WaitForChild("Modules"):WaitForChild("SkillTuning"))
end)
if not ok or type(T) ~= "table" then
	warn("[SkillCast] SkillTuning missing; using DEFAULT", T)
	T = DEFAULT
end

-- harden
T.Skills        = T.Skills        or DEFAULT.Skills
T.CD            = T.CD            or DEFAULT.CD
T.FIRE_RANGE    = T.FIRE_RANGE    or DEFAULT.FIRE_RANGE
T.QUAKE_RANGE   = T.QUAKE_RANGE   or DEFAULT.QUAKE_RANGE
T.AQUA_DURATION = T.AQUA_DURATION or DEFAULT.AQUA_DURATION
T.MAX_LEVEL     = T.MAX_LEVEL     or DEFAULT.MAX_LEVEL

local ALIAS = {
	fire="firebolt", bolt="firebolt", firebolt="firebolt",
	aquaburst="aquabarrier", aquabarrier="aquabarrier", watershield="aquabarrier",
	quake="quakepulse", quakepulse="quakepulse",
}
local function norm(id) return ALIAS[string.lower(tostring(id or ""))] end

local function primaryPart(model)
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChildWhichIsA("BasePart")
end
local function livingHumanoid(model)
	local h = model and model:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then return h end
end

local function getPlotFor(plr)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _, m in ipairs(plots:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == plr.UserId then
			return m
		end
	end
end
local function getHero(plr)
	local plot = getPlotFor(plr)
	if not plot then return end
	local hero = plot:FindFirstChild("Hero", true)
	if hero and hero:IsA("Model") then return hero, plot end
end

local function enemiesIn(plot)
	local list = {}
	if not plot then return list end
	local arena  = plot:FindFirstChild("Arena")
	local folder = arena and arena:FindFirstChild("Enemies")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then table.insert(list, m) end
		end
	else
		for _, m in ipairs(workspace:GetDescendants()) do
			if m:IsA("Model") and (m:GetAttribute("IsEnemy") or m.Name == "Enemy") then
				table.insert(list, m)
			end
		end
	end
	return list
end

local function nearestEnemy(plot, fromPos, maxRange)
	local best, bestDist
	for _, m in ipairs(enemiesIn(plot)) do
		local hum = livingHumanoid(m)
		local pp  = primaryPart(m)
		if hum and pp then
			local d = (fromPos - pp.Position).Magnitude
			if d <= maxRange and (not bestDist or d < bestDist) then
				best, bestDist = m, d
			end
		end
	end
	return best
end

local function popNumber(amount, pos, color, kind)
	if RE_DMG then
		RE_DMG:FireAllClients({ amount = amount, pos = pos, color = color, kind = kind })
	end
end

local cd = {}
local function onCooldown(plr, key, waitSec)
	local now = os.clock()
	cd[plr] = cd[plr] or {}
	if (cd[plr][key] or 0) > now then return true end
	cd[plr][key] = now + waitSec
	return false
end
Players.PlayerRemoving:Connect(function(plr) cd[plr] = nil end)

local function fireboltDamage(lv)
	local s = T.Skills.firebolt
	local L = math.clamp(lv or 1, 1, T.MAX_LEVEL)
	return s.hit[L]
end
local function quakeDamage(lv)
	local s = T.Skills.quakepulse
	local L = math.clamp(lv or 1, 1, T.MAX_LEVEL)
	return s.hit[L]
end

local FRACTURED = setmetatable({}, { __mode = "k" })
local function markFracture(enemyModel, plr)
	if not enemyModel then return end
	local dur = tonumber((T.Skills.quakepulse and T.Skills.quakepulse.fractureDur) or 4.0) or 4.0
	FRACTURED[enemyModel] = { by = plr, untilT = os.clock() + dur }
end
local function hasFractureFrom(enemyModel, plr)
	local rec = enemyModel and FRACTURED[enemyModel]
	return rec and rec.by == plr and os.clock() < rec.untilT
end

local function castFirebolt(plr, lv, hero, plot)
	if onCooldown(plr, "firebolt", T.CD.firebolt) then return end
	local hpp = primaryPart(hero); if not hpp then return end
	local target = nearestEnemy(plot, hpp.Position, T.FIRE_RANGE); if not target then return end
	local tpp = primaryPart(target); if not tpp then return end
	local hum = livingHumanoid(target); if not hum then return end

	local dmg = fireboltDamage(lv)
	if hasFractureFrom(target, plr) then dmg = math.floor(dmg * 1.15 + 0.5) end

	-- route through Combat to pick up style/mastery/element
	local _, applied = Combat.ApplyDamage(plr, target, dmg, "Fire", false)

	if RE_VFX then
		RE_VFX:FireAllClients({
			kind = "firebolt",
			from = hpp.Position + Vector3.new(0, 2.8, 0),
			to   = tpp.Position + Vector3.new(0, 2.0, 0)
		})
	end
	popNumber(applied, tpp.Position, Color3.fromRGB(255, 220, 140), "skill")

	-- Lv5 DoT
	if lv >= 5 then
		local total = math.floor(fireboltDamage(lv) * 0.45 + 0.5)
		if hasFractureFrom(target, plr) then total = math.floor(total * 1.15 + 0.5) end
		local perTick = math.max(1, math.floor(total / 4 + 0.5))
		task.spawn(function()
			for i = 1, 4 do
				if hum.Health <= 0 then break end
				local _, tickApplied = Combat.ApplyDamage(plr, target, perTick, "Fire", false)
				popNumber(tickApplied, tpp.Position, Color3.fromRGB(255, 140, 100), "skill")
				task.wait(1.0)
			end
		end)
	end
end

local function castAquaBarrier(plr, lv, hero, plot)
	if onCooldown(plr, "aquabarrier", T.CD.aquabarrier) then return end
	local hpp = primaryPart(hero); if not hpp then return end
	local hum = livingHumanoid(hero); if not hum then return end

	local S = (T.Skills and T.Skills.aquabarrier) or {}
	local L = math.clamp(lv or 1, 1, T.MAX_LEVEL)

	local shield    = tonumber((S.shield    and S.shield[L])   or 0)  or 0
	local total     = tonumber((S.dotTotal  and S.dotTotal[L]) or 0)  or 0
	local ticks     = tonumber(S.dotTicks)  or 5
	local radius    = tonumber(S.dotRadius) or T.QUAKE_RANGE
	local perTick   = math.max(1, math.floor(total / math.max(1, ticks) + 0.5))
	local duration  = tonumber(S.duration) or T.AQUA_DURATION or 6

	-- trigger conditions (enemies near + low-ish HP)
	local triggerRange = (S.triggerRange or 12)
	local triggerCount = (S.triggerEnemyCount or 1)
	local nearby = 0
	for _, enemy in ipairs(enemiesIn(plot)) do
		local eh, pp = livingHumanoid(enemy), primaryPart(enemy)
		if eh and pp and (pp.Position - hpp.Position).Magnitude <= triggerRange then
			nearby += 1
			if nearby >= triggerCount then break end
		end
	end
	if nearby < triggerCount then return end

	local hpThresh = (T.Client and T.Client.AQUA_HP_THRESHOLD) or 0.75
	if (hum.Health / math.max(1, hum.MaxHealth)) > hpThresh then return end

	-- ========= shield: add-on over durable baseline (Aegis) =========
	local base   = tonumber(hero:GetAttribute("ShieldBaseMax")) or 0  -- set by Aegis, else 0
	local curHP  = tonumber(hero:GetAttribute("ShieldHP"))      or 0
	local add    = math.max(0, shield)
	local newHP  = curHP + add
	local newMax = math.max(base, newHP)
	local expAt  = os.clock() + duration

	hero:SetAttribute("ShieldHP",      newHP)
	hero:SetAttribute("ShieldMax",     newMax)
	hero:SetAttribute("ShieldExpireAt", expAt)   -- timed part only
	hero:SetAttribute("BarrierUntil",   expAt)

	-- number popup shows the added amount
	if add > 0 then
		popNumber(add, hpp.Position + Vector3.new(0, 2.2, 0), Color3.fromRGB(90,180,255), "shield")
	end

	if RE_VFX then
		RE_VFX:FireAllClients({
			kind     = "aquabarrier",
			pos      = hpp.Position,
			duration = duration,
			who      = hero,
		})
	end

	-- on expiry: clamp to durable baseline (if any)
	task.delay(duration, function()
		if hero and hero.Parent then
			local now = os.clock()
			if (hero:GetAttribute("ShieldExpireAt") or 0) <= now then
				local baseMax = tonumber(hero:GetAttribute("ShieldBaseMax")) or 0
				local cur     = tonumber(hero:GetAttribute("ShieldHP")) or 0
				hero:SetAttribute("ShieldMax",     baseMax)
				hero:SetAttribute("ShieldHP",      baseMax > 0 and math.min(cur, baseMax) or 0)
				hero:SetAttribute("ShieldExpireAt", 0)
				hero:SetAttribute("BarrierUntil",   0)
				if RE_VFX then RE_VFX:FireAllClients({ kind = "aquabarrier_kill", who = hero }) end
			end
		end
	end)
	-- ================================================================

	-- DoT aura (damage via Combat)
	task.spawn(function()
		for _ = 1, ticks do
			if not livingHumanoid(hero) then break end
			local center = primaryPart(hero).Position
			for _, enemy in ipairs(enemiesIn(plot)) do
				local eh, pp = livingHumanoid(enemy), primaryPart(enemy)
				if eh and pp and (pp.Position - center).Magnitude <= radius then
					local _, tickApplied = Combat.ApplyDamage(plr, enemy, perTick, "Water", false)
					popNumber(tickApplied, pp.Position, Color3.fromRGB(120,180,255), "skill")
				end
			end
			task.wait(1.0)
		end
	end)

	-- Lv5 HoT (unchanged)
	if L >= T.MAX_LEVEL then
		local hotTotal = tonumber(S.hotTotalLv5) or 50
		local hotTicks = tonumber(S.hotTicks)    or 5
		local hotPer   = math.max(1, math.floor(hotTotal / math.max(1, hotTicks) + 0.5))
		task.spawn(function()
			for _ = 1, hotTicks do
				if not livingHumanoid(hero) then break end
				local before = hum.Health
				hum.Health = math.min(hum.MaxHealth, hum.Health + hotPer)
				local healed = math.floor(hum.Health - before + 0.5)
				if healed > 0 then
					popNumber(healed, hpp.Position + Vector3.new(0, 2.2, 0), Color3.fromRGB(120,255,140), "heal")
				end
				task.wait(1.0)
			end
		end)
	end
end

local function castQuakePulse(plr, lv, hero, plot)
	if onCooldown(plr, "quakepulse", T.CD.quakepulse) then return end
	local hpp = primaryPart(hero); if not hpp then return end

	local radius = T.QUAKE_RANGE
	if RE_VFX then
		RE_VFX:FireAllClients({ kind = "quakepulse", pos = hpp.Position, radius = radius })
	end

	local base = quakeDamage(lv)
	for _, enemy in ipairs(enemiesIn(plot)) do
		local hum, pp = livingHumanoid(enemy), primaryPart(enemy)
		if hum and pp and (pp.Position - hpp.Position).Magnitude <= radius then
			local _, applied = Combat.ApplyDamage(plr, enemy, base, "Earth", false)
			markFracture(enemy, plr)
			popNumber(applied, pp.Position, Color3.fromRGB(255, 210, 120), "skill")
		end
	end

	task.delay(1.0, function()
		local half = math.floor(base * 0.5 + 0.5)
		for _, enemy in ipairs(enemiesIn(plot)) do
			local hum, pp = livingHumanoid(enemy), primaryPart(enemy)
			if hum and pp and (pp.Position - hpp.Position).Magnitude <= radius then
				local _, applied = Combat.ApplyDamage(plr, enemy, half, "Earth", false)
				popNumber(applied, pp.Position, Color3.fromRGB(255, 200, 120), "skill")
			end
		end
	end)
end

RE_Cast.OnServerEvent:Connect(function(plr, payload)
	if typeof(payload) ~= "table" then return end

	local hero, plot = getHero(plr); if not hero then return end
	local hum = hero:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then return end
	if plot and plot:GetAttribute("CombatLocked") then return end

	local which = norm(payload.kind or payload.id); if not which then return end
	local equipped = norm(plr:GetAttribute("Equip_Primary"))
	if not equipped or which ~= equipped then return end

	local lv = tonumber(plr:GetAttribute("Skill_" .. which)) or 0
	if lv <= 0 then return end

	if which == "firebolt" then
		castFirebolt(plr, lv, hero, plot)
	elseif which == "aquabarrier" then
		castAquaBarrier(plr, lv, hero, plot)
	elseif which == "quakepulse" then
		castQuakePulse(plr, lv, hero, plot)
	end
end)

print(("[SkillCast] online. FIRE_RANGE=%d QUAKE_RANGE=%d AQUA_DUR=%d")
	:format(T.FIRE_RANGE, T.QUAKE_RANGE, T.AQUA_DURATION))
