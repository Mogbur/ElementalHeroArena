-- ServerScriptService/RojoServer/Modules/HeroBrain.lua

local Players            = game:GetService("Players")
local CollectionService  = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Debris             = game:GetService("Debris")
local RunService         = game:GetService("RunService")

local DamageNumbers = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DamageNumbers"))

-- Optional VFX bus
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_VFX  = Remotes:WaitForChild("SkillVFX", 10)

local Brain  = {}
local ACTIVE = setmetatable({}, { __mode = "k" })

local T = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SkillTuning"))

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

-- ========= combat brain =========

function Brain.attach(hero: Model)
	if ACTIVE[hero] then return ACTIVE[hero] end

	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
	if not (hum and hrp and hrp:IsA("BasePart")) then
		warn("[HeroBrain] Missing Humanoid/Root on", hero:GetFullName())
		return
	end

	ensureShieldAttrs(hero)
	hum.WalkSpeed = 13
	hum.AutoRotate, hum.Sit, hum.PlatformStand = true, false, false
	hrp.CanCollide = false
	for _, d in ipairs(hero:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end
	task.defer(function() pcall(function() hrp:SetNetworkOwner(nil) end) end)

	-- billboard + visibility toggle
	local gui, hpFill, shFill, hpWrap, shWrap = buildBillboard(hero, hum, hrp)
	local function syncBarsVisible()
		gui.Enabled = (hero:GetAttribute("BarsVisible") ~= 0)
	end
	syncBarsVisible()
	hero:GetAttributeChangedSignal("BarsVisible"):Connect(syncBarsVisible)
	refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)

	-- owner routing
	local OWNER_ID = hero:GetAttribute("OwnerUserId") or 0
	do
		local plot = hero:FindFirstAncestorWhichIsA("Model")
		if OWNER_ID == 0 and plot then OWNER_ID = plot:GetAttribute("OwnerUserId") or 0 end
	end

	-- tuning
	local ATTACK_RANGE   = 6.0
	local MELEE_DAMAGE   = 15
	local SWING_COOLDOWN = 0.60
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

	local function pickTarget(): Instance?
		local best, bestDist
		for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
			if isMyEnemy(e) then
				local p = targetPos(e)
				if p then
					local d = (p - hrp.Position).Magnitude
					if not best or d < bestDist then best, bestDist = e, d end
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

	local function findPlot(): Model? return hero:FindFirstAncestorWhichIsA("Model") end
	local function isCombatLocked(): boolean
		local plot = findPlot()
		return plot and (plot:GetAttribute("CombatLocked") == true) or false
	end

	-- crits
	local function getCritParams()
		local chance, mult = 0.05, 2.0
		local plot = findPlot()
		if plot then
			chance = plot:GetAttribute("CritChance") or chance
			mult = plot:GetAttribute("CritMult")  or mult
		end
		chance = hero:GetAttribute("CritChance") or chance
		mult   = hero:GetAttribute("CritMult")  or mult
		return math.clamp(chance, 0, 1), math.max(1, mult)
	end

	local function applyDamage(target: Instance, amount: number, color: Color3?, allowCrit: boolean?)
		if amount <= 0 then return 0,false end
		local isCrit = false
		if allowCrit ~= false then
			local c,m = getCritParams()
			if math.random() < c then amount = amount * m; isCrit = true end
		end
		local dealt = amount
		local h2 = target:FindFirstChildOfClass("Humanoid")
		local pp = (target:IsA("Model") and (target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart))
			or (target:IsA("BasePart") and target)
		if h2 then
			h2:TakeDamage(dealt)
		else
			local hp = target:GetAttribute("Health")
			if hp then target:SetAttribute("Health", math.max(0, hp - dealt)) end
		end
		if pp then
			local shown = math.floor(dealt + 0.5)
			if isCrit then
				DamageNumbers.pop(pp, shown, Color3.fromRGB(255,90,90), {duration=1.35, rise=10, sizeMul=1.35})
			else
				DamageNumbers.pop(pp, shown, color or Color3.fromRGB(255,235,130))
			end
		end
		return dealt, isCrit
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

	local function canUseSkill(id: string): boolean
		id = canon(id); if not id then return false end
		if getSkillLevel(id) <= 0 then return false end
		local now = time()
		return (now >= (skillCDEnds[id] or 0)) and (now >= gcdEnds)
	end

	local function startCooldowns(id: string)
		id = canon(id); if not id then return end
		local now = time()
		skillCDEnds[id] = now + (COOLDOWN[id] or 6)
		gcdEnds = now + GCD_SECONDS
	end

	-- ===== Shield absorption (blue numbers) =====
	do
		local reenter = false
		local lastHealth = hum.Health
		hum.HealthChanged:Connect(function(newHealth)
			if reenter then return end
			local old = lastHealth; lastHealth = newHealth
			if newHealth >= old then
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
				return
			end

			local incoming = old - newHealth
			local s  = hero:GetAttribute("ShieldHP") or 0
			if s <= 0 then
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
				return
			end

			local absorbed = math.min(incoming, s)
			if absorbed > 0 then
				hero:SetAttribute("ShieldHP", s - absorbed)

				-- refund HP that shield took
				reenter = true
				hum.Health = math.min(hum.MaxHealth, hum.Health + absorbed)
				reenter = false
				lastHealth = hum.Health

				local pp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
				if pp then
					DamageNumbers.pop(pp, math.floor(absorbed+0.5), Color3.fromRGB(90,180,255))
				end

				if (s - absorbed) <= 0 then
					hero:SetAttribute("ShieldExpireAt", 0)
					if RE_VFX then RE_VFX:FireAllClients({ kind = "aquabarrier_kill", who = hero }) end
				end
			end
			refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
		end)

		hero.AttributeChanged:Connect(function(a)
			if a == "ShieldHP" or a == "ShieldMax" then
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
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
			applyDamage(target, base, Color3.fromRGB(255,140,70), true)
			local dotFrac = fireboltDotFrac(lv)
			if dotFrac > 0 then
				local perTick = base * (dotFrac/3)
				for i=1,3 do
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

		local S = T.Skills.aquabarrier or {}
		local L = math.clamp(lv, 1, T.MAX_LEVEL)

		-- Shield
		local shieldMax = (S.shield and S.shield[L]) or 0
		local duration  = tonumber(S.duration) or (T.AQUA_DURATION or 6)

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
			local hotTotal = tonumber(S.hotTotalLv5) or 50
			local hotTicks = tonumber(S.hotTicks)    or 5
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
			local total   = (S.dotTotal and S.dotTotal[L]) or 0
			local ticks   = tonumber(S.dotTicks)  or 5
			local radius  = tonumber(S.dotRadius) or 10
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

	local lastMelee = 0
	local function tryMelee(target: Instance): boolean
		local p = targetPos(target); if not p then return false end
		local dist = (p - hrp.Position).Magnitude
		if dist > ATTACK_RANGE then return false end
		if time() - lastMelee < SWING_COOLDOWN then return true end
		lastMelee = time()
		faceTowards(hrp, p)
		hero:SetAttribute("MeleeTick", os.clock())
		applyDamage(target, MELEE_DAMAGE, Color3.fromRGB(255,235,130), true)
		return true
	end

	-- lifetime
	local conns = {}
	table.insert(conns, hero.Destroying:Connect(function() Brain.detach(hero) end))

	local running = true
	ACTIVE[hero] = { conns = conns, hum = hum, hrp = hrp, running = running }

	-- Shield expiry
	table.insert(conns, RunService.Heartbeat:Connect(function()
		local hp  = hero:GetAttribute("ShieldHP") or 0
		if hp > 0 then
			local t = hero:GetAttribute("ShieldExpireAt") or 0
			if os.clock() >= t and t > 0 then
				hero:SetAttribute("ShieldHP", 0)
				hero:SetAttribute("ShieldMax", 0)
				hero:SetAttribute("ShieldExpireAt", 0)
				if RE_VFX then RE_VFX:FireAllClients({ kind = "aquabarrier_kill", who = hero }) end
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
			end
		end
	end))

	-- main loop
	task.spawn(function()
		while running and hero.Parent do
			task.wait(REPATH_EVERY)

			if hum.Health <= 0 then
				repeat task.wait(0.25) until hum.Health > 0 or not hero.Parent
				refreshBars(hero, hum, hpFill, shFill, hpWrap, shWrap)
			end

			-- If the plot is in a locked state (countdown / between waves), do nothing.
			if isCombatLocked() then
				hum:MoveTo(hrp.Position)
				continue
			end

			local target = pickTarget()
			local equipped = getEquippedSkill()

			-- emergency water (require nearby enemies)
			if equipped == "aquabarrier" and canUseSkill("aquabarrier") then
				local hpFrac = hum.Health / math.max(1, hum.MaxHealth)
				local needHP = (T.Client and T.Client.AQUA_HP_THRESHOLD) or 0.75
				if hpFrac <= needHP then
					if enemiesNear(hrp.Position, 12) >= 2 then
						cast_aquabarrier(getSkillLevel("aquabarrier"))
						startCooldowns("aquabarrier")
						continue
					end
				end
			end

			if target then
				-- quake
				if equipped == "quakepulse" and canUseSkill("quakepulse") then
					local hits = getEnemiesInCone(hrp.Position, hrp.CFrame.LookVector, QUAKE_RANGE, QUAKE_ANGLE)
					if #hits >= (T.Client and T.Client.QUAKE_MIN_ENEMIES or 2) then
						cast_quake(target, getSkillLevel("quakepulse"))
						startCooldowns("quakepulse")
						continue
					end
				end

				-- firebolt
				if equipped == "firebolt" and canUseSkill("firebolt") then
					local p = targetPos(target)
					if p and (p - hrp.Position).Magnitude <= FIRE_RANGE then
						cast_firebolt(target, getSkillLevel("firebolt"))
						startCooldowns("firebolt")
						continue
					end
				end

				-- melee / move-to
				if not tryMelee(target) then
					local p = targetPos(target)
					if p then
						local stopAt = math.max(ATTACK_RANGE - 1.0, 2.0)
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
