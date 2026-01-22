-- ServerScriptService/RojoServer/Modules/HeroBrain.lua

local Players            = game:GetService("Players")
local CollectionService  = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Debris             = game:GetService("Debris")
local RunService         = game:GetService("RunService")

-- show the old server-built hero bar? (leave OFF; we use the new client HUD)
local ENABLE_SERVER_HERO_BARS = false

local Styles  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponStyles"))
local Mastery = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StyleMastery"))
local T       = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SkillTuning"))
local DamageNumbers = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DamageNumbers"))
local SSS = game:GetService("ServerScriptService")
local Combat do
	local rs = SSS:FindFirstChild("RojoServer")
	local mods = rs and rs:FindFirstChild("Modules")
	local c = mods and mods:FindFirstChild("Combat")
	if not c then
		error("[HeroBrain] Combat module not found at ServerScriptService/RojoServer/Modules/Combat")
	end
	Combat = require(c)
end

-- Optional VFX bus
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_VFX  = Remotes:WaitForChild("SkillVFX", 10)
local RE_CVFX = Remotes:WaitForChild("CombatVFX", 10)

local Brain  = {}
local ACTIVE = setmetatable({}, { __mode = "k" })

-- show/hide the small separate shield bar under HP
local SHOW_SHIELD_SUBBAR = false

-- ========= utils =========

local function targetPos(t: Instance): Vector3?
	if not t then return nil end
	if t:IsA("Model") then
		local root = t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
		if root and root:IsA("BasePart") then return root.Position end
		local h2 = t:FindFirstChildOfClass("Humanoid")
		if h2 and h2.RootPart then return h2.RootPart.Position end
	elseif t:IsA("BasePart") then
		return t.Position
	end
end

local function faceTowards(hrp: BasePart, pos: Vector3)
	local look = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
	hrp.CFrame = CFrame.lookAt(hrp.Position, look)
end

local function softStopPoint(fromPos: Vector3, toPos: Vector3, stopAt: number): Vector3
	local dir = (toPos - fromPos)
	local dist = dir.Magnitude
	if dist < 1e-3 then return toPos end
	dir = dir / dist
	return toPos - dir * math.max(stopAt, 0)
end

-- ========= world bars (HP + Shield) =========

local function ensureShieldAttrs(hero: Model)
	if hero:GetAttribute("ShieldHP")       == nil then hero:SetAttribute("ShieldHP", 0) end
	if hero:GetAttribute("ShieldMax")      == nil then hero:SetAttribute("ShieldMax", 0) end
	if hero:GetAttribute("ShieldExpireAt") == nil then hero:SetAttribute("ShieldExpireAt", 0) end
end

local function buildBillboard(hero: Model, hum: Humanoid, hrp: BasePart)
	local old = hero:FindFirstChild("HeroBillboard"); if old then old:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HeroBillboard"
	gui.Adornee = hrp
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(150, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.0, 0)
	gui.Parent = hero

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1,1)
	root.Parent = gui

	local function mkBar(h: number)
		local wrap = Instance.new("Frame")
		wrap.BackgroundColor3 = Color3.fromRGB(0,0,0)
		wrap.BackgroundTransparency = 0.35
		wrap.BorderSizePixel = 0
		wrap.Size = UDim2.new(1, -8, 0, h)
		wrap.Position = UDim2.new(0, 4, 1, -(h+4))
		wrap.Parent = root
		Instance.new("UICorner", wrap).CornerRadius = UDim.new(0, 6)
		local stroke = Instance.new("UIStroke", wrap); stroke.Thickness = 1; stroke.Transparency = 0.35

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = Color3.fromRGB(110,235,125) -- HP green
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1,1)
		fill.Parent = wrap
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
		return wrap, fill
	end

	local hpWrap, hpFill = mkBar(10)
	hpWrap.Name, hpFill.Name = "HPBar", "HPFill"

	local shWrap, shFill
	if SHOW_SHIELD_SUBBAR then
		shWrap, shFill = mkBar(7)
		shWrap.Name, shFill.Name = "ShieldBar", "ShieldFill"
		shWrap.Position = UDim2.new(0, 4, 1, -(10+7+6))
		shFill.BackgroundColor3 = Color3.fromRGB(80,160,255)
		shWrap.Visible, shFill.Visible = false, false
	else
		shWrap, shFill = nil, nil
	end

	return gui, hpFill, shFill, hpWrap, shWrap
end

local function refreshBars(hero: Model, hum: Humanoid, hpFill: Frame, shFill: Frame, hpWrap: Frame, shWrap: Frame)
	if not (hum and hpFill) then return end
	local hpFrac = (hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth) or 0
	hpFill.Size = UDim2.fromScale(math.clamp(hpFrac, 0, 1), 1)

	local s   = hero:GetAttribute("ShieldHP")  or 0
	local max = hero:GetAttribute("ShieldMax") or 0
	if s > 0 and max <= 0 then max = s end
	local show = (max > 0 and s > 0)
	if shFill and shWrap then
		shWrap.Visible = show; shFill.Visible = show
		local frac = (max > 0) and (s / max) or 0
		shFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	end
end
local function applySlow(target: Instance, pct: number, dur: number)
    pct  = math.clamp(pct or 0.3, 0, 0.95) -- 30% default
    dur  = math.max(0.1, dur or 2.0)

    -- Debuff window for HUD/VFX
    local nowT = time()
    target:SetAttribute("SlowStartAt", nowT)
    target:SetAttribute("SlowDuration", dur)
    target:SetAttribute("SlowUntil",   nowT + dur)
    target:SetAttribute("SlowPct",     pct)

    -- Movement slow (optional; comment out if you don’t want it yet)
    local hum = target:FindFirstChildOfClass("Humanoid")
    local pre
    if hum then
        pre = hum.WalkSpeed
        hum.WalkSpeed = math.max(2, math.floor(pre * (1 - pct) + 0.5))
    end
    task.delay(dur, function()
        -- clear window
        if time() >= (tonumber(target:GetAttribute("SlowUntil")) or 0) - 0.01 then
            target:SetAttribute("SlowStartAt", 0)
            target:SetAttribute("SlowDuration", 0)
            target:SetAttribute("SlowUntil", 0)
            target:SetAttribute("SlowPct", 0)
        end
        if hum and hum.Parent and pre then hum.WalkSpeed = pre end
    end)

    -- Attack-speed slow: set an attribute your Enemy AI can read when deciding attack cadence
    -- (In your enemy brains, multiply their attack cooldown by (1 + pct) if SlowUntil > now)
    target:SetAttribute("AttackSpdSlowMul", 1 + pct)
end

-- ========= combat brain =========

function Brain.attach(hero: Model)
	if ACTIVE[hero] then return ACTIVE[hero] end

	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
	do
		local old = hero:FindFirstChild("HeroBillboard")
		if old then old:Destroy() end
	end
	if not (hum and hrp and hrp:IsA("BasePart")) then
		warn("[HeroBrain] Missing Humanoid/Root on", hero:GetFullName())
		return
	end
	if hero:GetAttribute("BaseMaxHealth") == nil then
		hero:SetAttribute("BaseMaxHealth", math.max(1, math.floor(hum.MaxHealth + 0.5)))
	end
	-- touch probe (optional): log parts that recently touched the hero
	local recentTouches = {}

	local function dumpRecentTouches()
		local now = os.clock()
		for name, t in pairs(recentTouches) do
			if now - t <= 1.0 then
				warn("[TouchProbe] recent touch ->", name)
			else
				recentTouches[name] = nil
			end
		end
	end

	-- track what touches the root (you can add more parts if you want)
	hrp.Touched:Connect(function(hit)
		if hit and hit.Parent then
			recentTouches[hit:GetFullName()] = os.clock()
			hero:SetAttribute("LastTouchName", hit:GetFullName())
		end
	end)

	-- === NON-COMBAT HEALTH DROP GUARD (only during spawn guard or idle) ===
	do
		local lastHP = hum.Health
		hum.HealthChanged:Connect(function(newHP)
			local prev = lastHP
			lastHP = newHP
			if newHP >= prev then return end
			
			-- ignore tiny jitter from physics/rounding
			local delta = prev - newHP
			if delta <= 0.5 then return end
			-- allow intentional server-side drops (soft revive)
			if hero:GetAttribute("GuardAllowDrop") == 1 then return end

			-- only guard during spawn guard or while idle (not mid-fight)
			local now    = os.clock()
			local untilT = math.max(
				tonumber(hero:GetAttribute("InvulnUntil")) or 0,
				tonumber(hero:GetAttribute("SpawnGuardUntil")) or 0
			)
			local inGuard = (now < untilT) or (hero:GetAttribute("DamageMute") == 1)

			local plot    = hero:FindFirstAncestorWhichIsA("Model")
			local inIdle  = (hero:GetAttribute("BarsVisible") or 0) == 0
				or (plot and plot:GetAttribute("AtIdle") == true)

			if not (inGuard or inIdle) then
				-- active combat: do not refund drops here
				return
			end

			-- real non-combat drop during guarded time → refund
			local lastCombatT = tonumber(hero:GetAttribute("LastCombatDamageAt")) or 0
			local dt = os.clock() - lastCombatT
			if dt > 0.06 then
				warn(("[GuardDbg] Blocked non-Combat damage Δ=%.1f (dt=%.2fs)"):format(prev - newHP, dt))
				hum.Health = math.max(prev, 1)
				hum:ChangeState(Enum.HumanoidStateType.Running)
				hum.Health = prev
			end
		end)
	end


	ensureShieldAttrs(hero)
	hum.WalkSpeed = 13
	hum.AutoRotate, hum.Sit, hum.PlatformStand = true, false, false
	pcall(function()
		hrp.CanCollide = (hrp.Name == "HumanoidRootPart")
	end)
	for _, d in ipairs(hero:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end
	task.defer(function() pcall(function() hrp:SetNetworkOwner(nil) end) end)

	-- client-side HeroHUD handles hero bars; only build the old server bar if explicitly enabled
	local gui, hpFill, shFill, hpWrap, shWrap
	if ENABLE_SERVER_HERO_BARS then
		gui, hpFill, shFill, hpWrap, shWrap = buildBillboard(hero, hum, hrp)
		local function syncBarsVisible()
			gui.Enabled = (hero:GetAttribute("BarsVisible") ~= 0)
		end
		syncBarsVisible()
		hero:GetAttributeChangedSignal("BarsVisible"):Connect(syncBarsVisible)
		refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
	end

	-- owner routing
	local OWNER_ID = hero:GetAttribute("OwnerUserId") or 0
	do
		local plot = hero:FindFirstAncestorWhichIsA("Model")
		if OWNER_ID == 0 and plot then OWNER_ID = plot:GetAttribute("OwnerUserId") or 0 end
	end
	local function getOwnerPlayer()
		if OWNER_ID and OWNER_ID ~= 0 then
			return Players:GetPlayerByUserId(OWNER_ID)
		end
	end

	-- === Style helpers (inside attach so they can see 'hero') ===
	local function currentStyleId()
		local main = (hero:GetAttribute("WeaponMain") or "Sword"):lower()
		local off  = (hero:GetAttribute("WeaponOff")  or ""):lower()
		if main == "bow"  then return "Bow" end
		if main == "mace" then return "Mace" end
		if main == "sword" and off == "shield" then return "SwordShield" end
		return "SwordShield"
	end

	local styleId, S, B
	local MELEE_DAMAGE   = 15
	local SWING_COOLDOWN = 0.60

	-- re-applied at wave start and when style attributes change
	local function applyStyle()
		styleId = currentStyleId()
		S = Styles[styleId] or Styles.SwordShield

		-- mastery bonuses
		local plr = getOwnerPlayer()
		local xp  = tonumber(plr and plr:GetAttribute("StyleXP_"..styleId)) or 0
		B = Mastery.bonuses(styleId, xp)

		-- canonical BASE max HP (remembered across style swaps)
		local lastMul = math.max(0.01, (plr and plr:GetAttribute("LastHpMul")) or 1)
		local baseMax = hero:GetAttribute("BaseMaxHealth")
		if not baseMax or baseMax <= 0 then
			baseMax = hum.MaxHealth / lastMul
		end
		baseMax = math.max(1, math.floor(baseMax + 0.5))

		-- === Core multipliers from the plot (HP & Haste) ===
		local plot     = hero:FindFirstAncestorWhichIsA("Model")
		local coreId   = plot and plot:GetAttribute("CoreId")
		local coreTier = tonumber(plot and plot:GetAttribute("CoreTier")) or 0
		local bonus    = 1 + 0.06 * coreTier

		local coreHpMul  = (coreId == "HP")  and bonus or 1
		local coreSpdMul = (coreId == "HST") and bonus or 1

		-- IMPORTANT: Do NOT pre-apply ATK here. Let Combat handle ATK core & OC.
		-- Keep the attribute around for old code paths, but neutralize it.
		hero:SetAttribute("__CoreAtkMul", 1)

		-- Max HP = base * style * core(HP)
		local newMax = math.floor(baseMax * (S.hpMul or 1.0) * coreHpMul + 0.5)
		local ratio  = hum.Health / math.max(1, hum.MaxHealth)

		-- whitelist this write so guards don’t “refund” it
		hero:SetAttribute("GuardAllowDrop", 1)
		hum.MaxHealth = newMax
		hum.Health    = math.clamp(math.floor(newMax * ratio + 0.5), 1, newMax)
		task.delay(0.20, function()
			if hero and hero.Parent then hero:SetAttribute("GuardAllowDrop", 0) end
		end)

		if plr then plr:SetAttribute("LastHpMul", S.hpMul or 1.0) end

		-- melee base damage from style (your old logic)
		local baseMelee = 15
		MELEE_DAMAGE = 15

		-- Basic swing cadence = base / (style * core(Haste))
		local baseSwing = 0.60
		SWING_COOLDOWN = baseSwing / math.max(0.2, (S.spdMul or 1.0) * coreSpdMul)
	end

	applyStyle()
	hero:GetAttributeChangedSignal("WeaponMain"):Connect(applyStyle)
	hero:GetAttributeChangedSignal("WeaponOff"):Connect(applyStyle)
	-- ALSO re-apply style when core changes on the owning plot
	do
		local function findPlot()
			local cur, best = hero.Parent, nil
			while cur do
				if cur:IsA("Model") and cur:GetAttribute("OwnerUserId") ~= nil then
					best = cur
				end
				cur = cur.Parent
			end
			return best
		end
		local plotRef = findPlot()
		if plotRef and hero:GetAttribute("__CoreWatchHooked") ~= 1 then
			hero:SetAttribute("__CoreWatchHooked", 1)
			plotRef:GetAttributeChangedSignal("CoreId"):Connect(applyStyle)
			plotRef:GetAttributeChangedSignal("CoreTier"):Connect(applyStyle)
		end
	end

	-- crit params (fold Bow mastery crit-damage here)
	local function getCritParams()
		local chance, mult = 0.05, 2.0
		local plot = hero:FindFirstAncestorWhichIsA("Model")
		if plot then
			chance = plot:GetAttribute("CritChance") or chance
			mult   = plot:GetAttribute("CritMult")   or mult
		end
		chance = hero:GetAttribute("CritChance") or chance
		mult   = hero:GetAttribute("CritMult")   or mult
		-- NOTE: Do NOT fold Bow mastery critDmgMul here: that would affect skills too.
		return math.clamp(chance, 0, 1), math.max(1, mult)
	end

	-- tuning
	local ATTACK_RANGE   = 6.0
	local REPATH_EVERY   = 0.25

	local GCD_SECONDS = T.GLOBAL_CD or 3.0
	local COOLDOWN    = {
		firebolt    = T.CD.firebolt,
		quakepulse  = T.CD.quakepulse,
		aquabarrier = T.CD.aquabarrier,
	}

	local QUAKE_RANGE, QUAKE_ANGLE = T.QUAKE_RANGE, 60.0
	local FIRE_RANGE = T.FIRE_RANGE

	local function fireboltDamage(lv)  return (T.Skills.firebolt.hit or {})[math.clamp(lv,1,T.MAX_LEVEL)] or 25 end
	local function fireboltDotFrac(lv) return (lv >= 5) and (T.Skills.firebolt.dotPctLv5 or 0.30) or 0 end
	local function quakeDamage(lv)     return (T.Skills.quakepulse.hit or {})[math.clamp(lv,1,T.MAX_LEVEL)] or 45 end
	local function quakeConeFrac(lv)   return 0.60 + 0.10 * (math.clamp(lv or 1, 1, T.MAX_LEVEL) - 1) end

	-- target filters
	local function isMyEnemy(m: Instance): boolean
		if not CollectionService:HasTag(m, "Enemy") then return false end
		local owner = m:GetAttribute("OwnerUserId")
		if owner and OWNER_ID ~= 0 and owner ~= OWNER_ID then return false end
		local h2 = m:FindFirstChildOfClass("Humanoid")
		return (not h2) or h2.Health > 0
	end

	local function currentHP(m)
		local hum2 = m:FindFirstChildOfClass("Humanoid")
		if hum2 then return hum2.Health end
		return m:GetAttribute("Health") or 1e9
	end

	local function pickTarget(): Instance?
		local best, bestScore
		for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
			if isMyEnemy(e) then
				local p = targetPos(e)
				if p then
					local d  = (p - hrp.Position).Magnitude
					local hp = currentHP(e)
					local finisherBias = (hp <= 20) and -8 or 0
					local score = d + finisherBias
					if not best or score < bestScore then
						best, bestScore = e, score
					end
				end
			end
		end
		return best
	end

	-- handy
	local function enemiesNear(pos: Vector3, range: number): number
		local n = 0
		for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
			if isMyEnemy(e) then
				local p = targetPos(e)
				if p and (p - pos).Magnitude <= range then
					n += 1
				end
			end
		end
		return n
	end
	local function currentSegId(plot)
		local w = tonumber(plot:GetAttribute("CurrentWave")) or 1
		return ((w - 1) // 5)
	end

	local function findPlot(): Model?
		-- start above the hero and remember the highest ancestor with OwnerUserId
		local cur = hero.Parent
		local best = nil
		while cur do
			if cur:IsA("Model") and cur:GetAttribute("OwnerUserId") ~= nil then
				best = cur
			end
			cur = cur.Parent
		end
		return best
	end

	local function getBlessElem()
		local plot = findPlot(); if not plot then return nil end
		local elemRaw = plot:GetAttribute("BlessingElem")
		local elem = tostring(elemRaw or ""):lower()
		local segNow  = currentSegId(plot)
		local expSeg  = tonumber(plot:GetAttribute("BlessingExpiresSegId")) or -999

		if (elem == "fire" or elem == "water" or elem == "earth") and (expSeg == segNow) then
			return elem
		end
		return nil
	end

	local function isCombatLocked(): boolean
		local plot = findPlot()
		return plot and (plot:GetAttribute("CombatLocked") == true) or false
	end

	-- ====== ADD/REPLACE HERE (inside Brain.attach, after getCritParams and before -- skills) ======
	-- Server-side damage helper:
	--  - Blocks self-hits (hero hitting their own rig)
	--  - Sends ALL damage through Combat.ApplyDamage so spawn guard / friendly-fire / shields / style work
	-- Server-side damage helper for basics
	-- Server-side damage helper for basics/skills
	local function applyDamage(target: Instance, amount: number, color: Color3?, allowCrit: boolean?, opts)
		if not target or amount <= 0 then return 0, false end
		opts = opts or {}

		-- never hit yourself
		if target:IsDescendantOf(hero) then return 0, false end

		-- IMPORTANT:
		--  - Do NOT roll crit here (Combat is the single authority).
		--  - Pass base damage as-is.
		--  - Pass isBasic so Combat can apply style/crit rules correctly.
		local ownerPlr = Players:GetPlayerByUserId(hero:GetAttribute("OwnerUserId") or 0)
		local _, applied = Combat.ApplyDamage(ownerPlr, target, amount, nil, opts.isBasic == true)

		-- damage numbers show what actually applied (after DR/shields/etc.)
		local m  = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
		local pp = (m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart))
			or (target:IsA("BasePart") and target)

		if pp and applied and applied > 0 then
			local shown = math.floor(applied + 0.5)
			-- NOTE: we no longer know "real crit" here; displayCrit is used for Bow surge visuals.
			if opts and opts.displayCrit then
				DamageNumbers.pop(pp, shown, Color3.fromRGB(255,90,90), {duration=1.35, rise=10, sizeMul=1.35})
			else
				DamageNumbers.pop(pp, shown, color or Color3.fromRGB(255,235,130))
			end
		end

		return applied or 0, false
	end

	local function applyHeal(model: Instance, amount: number)
		local h = model:FindFirstChildOfClass("Humanoid")
		if not (h and h.Health > 0) then return end
		h.Health = math.min(h.MaxHealth, h.Health + amount)
		local pp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if pp then DamageNumbers.pop(pp, "+"..math.floor(amount+0.5), Color3.fromRGB(120,255,140)) end
	end

	-- skills
	local function canon(id: string?): string?
		if not id then return nil end
		id = id:lower()
		if id == "aquabarrier" or id == "aquaburst" or id == "watershield" or id == "water" then
			return "aquabarrier"
		end
		if id == "quakepulse" or id == "quake" or id == "earth" then
			return "quakepulse"
		end
		if id == "firebolt" or id == "fire" or id == "bolt" then
			return "firebolt"
		end
		return id
	end

	local function getEquippedSkill(): string?
		local id = hero:GetAttribute("Equip_Primary")
		if not id or id == "" then
			local plot = findPlot()
			id = plot and plot:GetAttribute("Equip_Primary")
		end
		return canon(id)
	end

	-- respect slots
	local function isEquipped(id: string?): boolean
		id = canon(id)
		if not id then return false end
		local p = getEquippedSkill()
		if id == p then return true end
		local u = canon(hero:GetAttribute("Equip_Utility"))
		if id == u then return true end
		local s2 = canon(hero:GetAttribute("Equip_Secondary"))
		if id == s2 then return true end
		return false
	end

	local function getSkillLevel(id: string): number
		id = canon(id) or ""
		if id == "" then return 0 end
		local lv = tonumber(hero:GetAttribute("Skill_"..id)) or 0
		if lv <= 0 then
			local plot = findPlot()
			lv = tonumber(plot and plot:GetAttribute("Skill_"..id)) or 0
		end
		return lv
	end

	local skillCDEnds = { firebolt=0, quakepulse=0, aquabarrier=0 }
	local gcdEnds = 0

	local function resetAllCooldowns()
		gcdEnds = 0
		for k,_ in pairs(skillCDEnds) do skillCDEnds[k] = 0 end
	end

	local function canUseSkill(id: string): boolean
		id = canon(id); if not id then return false end
		if getSkillLevel(id) <= 0 then return false end
		local now = time()
		return (now >= (skillCDEnds[id] or 0)) and (now >= gcdEnds) and isEquipped(id)
	end

	local function startCooldowns(id: string)
		id = canon(id); if not id then return end
		local now = time()
		skillCDEnds[id] = now + (COOLDOWN[id] or 6)
		gcdEnds = now + GCD_SECONDS
	end

	-- ===== damage intake (UI refresh only; DR/Guard handled in Combat) =====
	if ENABLE_SERVER_HERO_BARS then
		hum.HealthChanged:Connect(function(_newHealth)
			refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
		end)

		hero.AttributeChanged:Connect(function(attrName)
			if attrName == "ShieldHP" or attrName == "ShieldMax" then
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
				if attrName == "ShieldHP" then
					local s  = hero:GetAttribute("ShieldHP") or 0
					local t  = hero:GetAttribute("ShieldExpireAt") or 0
					if s <= 0 and t > 0 and RE_VFX then
						hero:SetAttribute("ShieldMax", 0)
						hero:SetAttribute("ShieldExpireAt", 0)
						RE_VFX:FireAllClients({ kind = "aquabarrier_kill", who = hero })
					end
				end
			end
		end)
	end

	-- ===== attacks =====

	local function cast_firebolt(target: Instance, lv: number)
		if not target or lv <= 0 then return end
		local p = targetPos(target); if not p then return end
		faceTowards(hrp, p)
		hero:SetAttribute("CastTick", "firebolt@"..tostring(os.clock()))

		local bolt = Instance.new("Part")
		bolt.Size = Vector3.new(0.4,0.4,0.4); bolt.Shape = Enum.PartType.Ball
		bolt.CanCollide = false; bolt.Anchored = true; bolt.Color = Color3.fromRGB(255,120,60)
		bolt.Position = (hrp.Position + Vector3.new(0,2,0)); bolt.Parent = workspace

		local dir = (p - bolt.Position).Unit
		local speed = 80
		local flight = (p - bolt.Position).Magnitude / speed

		task.spawn(function()
			local t0 = time()
			while time() - t0 < flight do
				bolt.CFrame = bolt.CFrame + dir * speed * task.wait()
			end
			bolt:Destroy()
			local base = fireboltDamage(lv)
			local be = getBlessElem()
			if be == "fire" then
				base = math.floor(base * ((T.BLESS and T.BLESS.FireDmgMul) or 1.20) + 0.5)
			end
			applyDamage(target, base, Color3.fromRGB(255,140,70), true)
			local dotFrac = fireboltDotFrac(lv)
			if dotFrac > 0 then
				local ticks = 3
				local dotDur = ticks -- seconds (1s per tick)
				-- mark debuff window for the client HUD/VFX
				local nowT = time()
				if target and target.Parent then
					target:SetAttribute("FireStartAt", nowT)
					target:SetAttribute("FireDuration", dotDur)
					target:SetAttribute("FireUntil", nowT + dotDur)
					-- Optional: set a custom icon per enemy type
					-- target:SetAttribute("FireIconId", "rbxassetid://YOUR_FIRE_ICON")
				end

				local perTick = base * (dotFrac / ticks)
				for i = 1, ticks do
					task.delay(i, function()
						if target and target.Parent then
							applyDamage(target, perTick, Color3.fromRGB(255,100,60), false)
						end
					end)
				end
			end
		end)
	end

	local function getEnemiesInCone(origin: Vector3, forward: Vector3, range: number, angleDeg: number)
		local list = {}
		for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
			if isMyEnemy(e) then
				local p = targetPos(e)
				if p then
					local v = (p - origin); local dist=v.Magnitude
					if dist <= range then
						local ang = math.deg(math.acos(math.clamp(forward:Dot(v.Unit), -1, 1)))
						if ang <= angleDeg then table.insert(list, e) end
					end
				end
			end
		end
		return list
	end

	local function cast_quake(target: Instance, lv: number)
		if lv <= 0 then return end
		local p = targetPos(target); if not p then return end
		faceTowards(hrp, p)
		hero:SetAttribute("CastTick", "quake@"..tostring(os.clock()))
		local hits = getEnemiesInCone(hrp.Position, hrp.CFrame.LookVector, QUAKE_RANGE, QUAKE_ANGLE)
		if #hits == 0 then return end
		local base = quakeDamage(lv) * quakeConeFrac(lv)
		local be = getBlessElem()
		if be == "earth" then
			base = math.floor(base * ((T.BLESS and T.BLESS.EarthDmgMul) or 1.20) + 0.5)
		end
		for _, e in ipairs(hits) do
			applyDamage(e, base, Color3.fromRGB(200,170,120), true)
		end
		local ring = Instance.new("Part")
		ring.Anchored=true; ring.CanCollide=false; ring.Transparency=0.4
		ring.Color=Color3.fromRGB(230,210,160); ring.Size=Vector3.new(1,0.2,1)
		ring.CFrame=CFrame.new(hrp.Position + Vector3.new(0,0.2,0)); ring.Parent=workspace
		TweenService:Create(ring, TweenInfo.new(0.3), {
			Size=Vector3.new(QUAKE_RANGE*2,0.2,QUAKE_RANGE*2), Transparency=1
		}):Play()
		Debris:AddItem(ring, 0.4)
	end

	local function cast_aquabarrier(lv: number)
		if lv <= 0 then return end
		hero:SetAttribute("CastTick", "aquabarrier@"..tostring(os.clock()))

		local SAqua = T.Skills.aquabarrier or {}
		local L = math.clamp(lv, 1, T.MAX_LEVEL)

		-- Shield
		local be = getBlessElem()
		local blessMul = (be == "water") and ((T.BLESS and T.BLESS.WaterShieldMul) or 1.20) or 1
		local shieldMax = math.floor(((SAqua.shield and SAqua.shield[L]) or 0) * blessMul + 0.5)
		local duration  = tonumber(SAqua.duration) or (T.AQUA_DURATION or 6)
		print(("[AquaDbg] L=%d base=%d bless=%s mul=%.2f final=%d")
			:format(L, (SAqua.shield and SAqua.shield[L]) or 0, tostring(be), blessMul, shieldMax))
		do local plot=findPlot()
			print(("[BlessDbg] plot=%s elem=%s expires=%s seg=%s")
				:format(plot and plot.Name or "nil",
						tostring(plot and plot:GetAttribute('BlessingElem')),
						tostring(plot and plot:GetAttribute('BlessingExpiresSegId')),
						tostring(plot and plot and currentSegId(plot) or "?")))
		end
		hero:SetAttribute("ShieldMax",      shieldMax)
		hero:SetAttribute("ShieldHP",       shieldMax)
		hero:SetAttribute("ShieldExpireAt", os.clock() + duration)

		local pp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
		if pp then DamageNumbers.pop(pp, "SHIELD +"..shieldMax, Color3.fromRGB(90,180,255)) end

		if RE_VFX then
			RE_VFX:FireAllClients({
				kind     = "aquabarrier",
				who      = hero,
				pos      = pp and pp.Position or nil,
				duration = duration,
			})
		end

		-- Lv5 HoT (green numbers)
		if L >= T.MAX_LEVEL then
			local hotTotal = tonumber(SAqua.hotTotalLv5) or 50
			local hotTicks = tonumber(SAqua.hotTicks)    or 5
			local per      = math.max(1, math.floor(hotTotal / math.max(1, hotTicks) + 0.5))
			task.spawn(function()
				for _ = 1, hotTicks do
					if hum and hum.Health > 0 then
						local before = hum.Health
						hum.Health = math.min(hum.MaxHealth, hum.Health + per)
						local healed = math.floor(hum.Health - before + 0.5)
						if healed > 0 and pp then
							DamageNumbers.pop(pp, "+"..healed, Color3.fromRGB(120,255,140))
						end
					end
					task.wait(1)
				end
			end)
		end

		-- DoT aura (independent of bubble, follows the hero)
		do
			local total   = (SAqua.dotTotal and SAqua.dotTotal[L]) or 0
			local ticks   = tonumber(SAqua.dotTicks)  or 5
			local radius  = tonumber(SAqua.dotRadius) or 10
			local perTick = math.max(1, math.floor(total / math.max(1, ticks) + 0.5))
			task.spawn(function()
				for _ = 1, ticks do
					local center = (hrp and hrp.Position)
					if not center then break end
					for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
						if isMyEnemy(e) then
							local p = targetPos(e)
							if p and (p - center).Magnitude <= radius then
								applyDamage(e, perTick, Color3.fromRGB(120,180,255), false)
							end
						end
					end
					task.wait(1.0)
				end
			end)
		end
	end

	local lastStunAt = {} -- [Instance] = time()
	local bowSwingCount = 0 -- VFX-only counter (damage is handled in Combat)

	local function tryMelee(target: Instance): boolean
		-- Resolve target position early; bail if we somehow lost it.
		local p = targetPos(target); if not p then return false end
		local dist = (p - hrp.Position).Magnitude

		-- =========================
		-- BOW: ranged "basic" shot
		-- =========================
		if styleId == "Bow" then
			local basicRange = T.BOW_BASIC_RANGE or T.FIRE_RANGE or 90
			if dist > basicRange then return false end

			-- swing rate limit
			local last = hero:GetAttribute("__lastSwing") or 0
			if time() - last < SWING_COOLDOWN then return true end
			hero:SetAttribute("__lastSwing", time())

			-- face, mark a swing tick (helps anims/IK), then fire a projectile
			faceTowards(hrp, p)
			hero:SetAttribute("MeleeTick", os.clock())
			-- VFX-only surge cadence (damage surge is in Combat)
			bowSwingCount += 1
			local isSurge = (bowSwingCount % 6) == 0

			-- simple projectile to the target point
			local from = hrp.Position + Vector3.new(0, 2, 0)
			local dir  = (p - from).Unit

			-- Send bow tracer (every shot). Surge just tweaks visuals & sound client-side.
			-- no surge on the shooter; surge will be spawned at the enemy impact when the hit lands
			if RE_CVFX then
				RE_CVFX:FireAllClients({ kind = "bow_shot", from = from, to = p, surge = false })
			end

			local bolt = Instance.new("Part")
			bolt.Size = Vector3.new(0.25, 0.25, 1.2)
			bolt.Anchored, bolt.CanCollide = true, false
			bolt.Color = Color3.fromRGB(240,240,240)
			bolt.CFrame = CFrame.lookAt(from, p)
			bolt.Parent = workspace

			local speed  = 110
			local flight = dist / speed
			task.spawn(function()
				local t0 = time()
				while time() - t0 < flight do
					bolt.CFrame = bolt.CFrame + dir * speed * task.wait()
				end
				bolt:Destroy()
				-- Surge VFX on the ENEMY impact (NOT on shooter)
				if isSurge and RE_CVFX then
					RE_CVFX:FireAllClients({ kind = "bow_surge_hit", pos = p })
				end

				-- IMPORTANT:
				--  - mark this as a BASIC hit so Combat applies Bow cadence/bonus.
				--  - no pre-mult for surge; pass displayCrit just for red numbers.
				applyDamage(target, MELEE_DAMAGE, Color3.fromRGB(255,235,130), false, {
					isBasic = true
				})
			end)
			return true
		end

		-- ============================
		-- SWORD / MACE: true melee hit
		-- ============================
		if dist > ATTACK_RANGE then return false end  -- uses top-level ATTACK_RANGE

		-- swing rate limit
		local last = hero:GetAttribute("__lastSwing") or 0
		if time() - last < SWING_COOLDOWN then return true end
		hero:SetAttribute("__lastSwing", time())

		faceTowards(hrp, p)
		hero:SetAttribute("MeleeTick", os.clock())
		-- tell clients to play the right whoosh for this swing
		if RE_CVFX then
			RE_CVFX:FireAllClients({
				kind  = "melee_swing",
				style = styleId,         -- "SwordShield" or "Mace"
				pos   = hrp.Position,
			})
		end
		-- mark as BASIC so style bonuses (e.g., Mace flags) apply in Combat
		applyDamage(target, MELEE_DAMAGE, Color3.fromRGB(255,235,130), true, { isBasic = true })
		return true
	end

	-- lifetime
	local conns = {}
	table.insert(conns, hero.Destroying:Connect(function() Brain.detach(hero) end))

	-- also reset CDs + (re)apply style when wave HUD turns on for the hero
	table.insert(conns, hero:GetAttributeChangedSignal("BarsVisible"):Connect(function()
		if hero:GetAttribute("BarsVisible") == 1 then
			resetAllCooldowns()
			applyStyle()
		end
	end))

	local running = true
	ACTIVE[hero] = { conns = conns, hum = hum, hrp = hrp, running = running }

	-- Shield expiry
	table.insert(conns, RunService.Heartbeat:Connect(function()
		local hp  = hero:GetAttribute("ShieldHP") or 0
		if hp > 0 then
			local t  = hero:GetAttribute("ShieldExpireAt") or 0
			local on = hero:GetAttribute("BarsVisible") == 1
			-- only tick down / expire during combat bars (NOT while idling)
			if on and t > 0 and os.clock() >= t then
				hero:SetAttribute("ShieldHP", 0)
				hero:SetAttribute("ShieldMax", 0)
				hero:SetAttribute("ShieldExpireAt", 0)
				if RE_VFX then RE_VFX:FireAllClients({ kind = "aquabarrier_kill", who = hero }) end
				if ENABLE_SERVER_HERO_BARS then
					refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
				end
			end
		end
	end))

	-- main loop
	local FIREBOLT_RANGE = T.FIREBOLT_RANGE or T.FIRE_RANGE
	-- ADD THIS: sanity check that your tuning values are being read
	print(("[Dbg] Ranges | bowBasic=%s | firebolt=%s | fallback FIRE_RANGE=%s")
		:format(tostring(T.BOW_BASIC_RANGE), tostring(FIREBOLT_RANGE), tostring(T.FIRE_RANGE)))
	task.spawn(function()
		while running and hero.Parent do
			task.wait(REPATH_EVERY)

			if hum.Health <= 0 then
				repeat task.wait(0.25) until hum.Health > 0 or not hero.Parent
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
			end

			if isCombatLocked() then
				hum:MoveTo(hrp.Position)
				continue
			end

			local target = pickTarget()

			-- Utility: AquaBarrier (only if equipped)
			if canUseSkill("aquabarrier") then
				local hpFrac = hum.Health / math.max(1, hum.MaxHealth)
				local needHP = (T.Client and T.Client.AQUA_HP_THRESHOLD) or 0.75
				if hpFrac <= needHP and enemiesNear(hrp.Position, 12) >= 1 then
					cast_aquabarrier(getSkillLevel("aquabarrier"))
					startCooldowns("aquabarrier")
					continue
				end
			end

			if target then
				if canUseSkill("quakepulse") then
					local hits = getEnemiesInCone(hrp.Position, hrp.CFrame.LookVector, QUAKE_RANGE, QUAKE_ANGLE)
					if #hits >= (T.Client and T.Client.QUAKE_MIN_ENEMIES or 2) then
						cast_quake(target, getSkillLevel("quakepulse"))
						startCooldowns("quakepulse")
						continue
					end
				end

				if canUseSkill("firebolt") then
					local p = targetPos(target)
					if p and (p - hrp.Position).Magnitude <= FIREBOLT_RANGE then
						cast_firebolt(target, getSkillLevel("firebolt"))
						startCooldowns("firebolt")
						continue
					end
				end

				-- melee / move-to
				if not tryMelee(target) then
					local p = targetPos(target)
					if p then
						local stopAt
						if styleId == "Bow" then
							local basicRange = T.BOW_BASIC_RANGE or T.FIRE_RANGE or 90
							-- Stand a bit INSIDE basic range so shooting starts immediately
							stopAt = math.max(2, math.min(basicRange - 2, 16))
						else
							stopAt = math.max(ATTACK_RANGE - 1.0, 2.0)
						end
						hum:MoveTo(softStopPoint(hrp.Position, p, stopAt))
					end
				end
			else
				hum:MoveTo(hrp.Position)
			end
		end
	end)

	return ACTIVE[hero]
end

function Brain.detach(hero: Model)
	local s = ACTIVE[hero]; if not s then return end
	for _,c in ipairs(s.conns or {}) do pcall(function() c:Disconnect() end) end
	local gui = hero:FindFirstChild("HeroBillboard"); if gui then gui:Destroy() end
	ACTIVE[hero] = nil
end

return Brain
