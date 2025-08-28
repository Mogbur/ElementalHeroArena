-- ServerScriptService/RojoServer/Modules/HeroBrain.lua
-- (crit-enabled + overshoot fix + AquaBarrier alias) — module version

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local DamageNumbers     = require(ReplicatedStorage.Modules.DamageNumbers)
local RE_VFX            = ReplicatedStorage:FindFirstChild("SkillVFX") -- optional, nil-safe

local Brain = {}
local ACTIVE = setmetatable({}, { __mode = "k" }) -- model -> state (weak keys)

local function targetPos(t: Instance): Vector3?
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

local function softStopPoint(fromPos: Vector3, toPos: Vector3, stopAt: number)
	local dir = (toPos - fromPos)
	local dist = dir.Magnitude
	if dist < 1e-3 then return toPos end
	dir = dir / dist
	return toPos - dir * math.max(stopAt, 0)
end

function Brain.attach(hero: Model, ctx)
	if ACTIVE[hero] then return ACTIVE[hero] end

	local hum  = hero:FindFirstChildOfClass("Humanoid")
	local hrp  = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
	if not (hum and hrp) then
		warn("[HeroBrain] Missing Humanoid/Root on", hero:GetFullName())
		return
	end

	-- ===== OWNERSHIP / MOVEMENT =====
	local OWNER_ID = hero:GetAttribute("OwnerUserId")
	if not OWNER_ID then
		local plot = hero:FindFirstAncestorWhichIsA("Model")
		if plot then OWNER_ID = plot:GetAttribute("OwnerUserId") end
	end
	OWNER_ID = OWNER_ID or 0

	hum.WalkSpeed = math.max(12, hum.WalkSpeed)
	hum.JumpPower = 0
	hum.UseJumpPower = false
	hum.AutoRotate = true
	hum.Sit = false
	hum.PlatformStand = false
	if hrp:IsA("BasePart") then hrp.CanCollide = false end
	for _, d in ipairs(hero:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end
	task.defer(function() pcall(function() hrp:SetNetworkOwner(nil) end) end)

	-- ===== TUNING =====
	local ATTACK_RANGE   = 6.0
	local MELEE_DAMAGE   = 15
	local SWING_COOLDOWN = 0.60
	local REPATH_EVERY   = 0.25

	local GCD_SECONDS = 3.0
	local COOLDOWN = { firebolt=6.0, quake=10.0, aquaburst=12.0 }

	local function fireboltDamage(lv) return 25 + 12*(lv-1) end
	local function fireboltDotFrac(lv) return (lv >= 5) and 0.30 or 0 end
	local function quakeDamage(lv) return 45 + 20*(lv-1) end
	local function quakeConeFrac(lv) return 0.60 + 0.10*(lv-1) end
	local QUAKE_RANGE, QUAKE_ANGLE = 10.0, 60.0
	local function aquaHeal(lv) return 40 + 18*(lv-1) end
	local AQUA_EMERGENCY_HP = 0.65

	local function isMyEnemy(m: Instance): boolean
		if not CollectionService:HasTag(m, "Enemy") then return false end
		local owner = m:GetAttribute("OwnerUserId")
		if owner and OWNER_ID ~= 0 and owner ~= OWNER_ID then return false end
		local h2 = m:FindFirstChildOfClass("Humanoid")
		return (not h2) or h2.Health > 0
	end

	local function pickTarget()
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

	-- ===== CRIT SYSTEM =====
	local function findPlot(): Model? return hero:FindFirstAncestorWhichIsA("Model") end
	local function getCritParams()
		local chance, mult = 0.05, 2.0
		local plot = findPlot()
		if plot then
			chance = plot:GetAttribute("CritChance") or chance
			mult   = plot:GetAttribute("CritMult")   or mult
		end
		chance = hero:GetAttribute("CritChance") or chance
		mult   = hero:GetAttribute("CritMult")   or mult
		chance = math.clamp(chance, 0, 1); mult = math.max(1, mult)
		return chance, mult
	end

	-- ===== DAMAGE / HEAL =====
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
				DamageNumbers.pop(pp, shown, Color3.fromRGB(255, 90, 90), {duration=1.35, rise=10, sizeMul=1.35})
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

	local function canonSkill(id: string?)
		if not id then return nil end
		local s = string.lower(id)
		if s == "watershield" or s == "aquabarrier" then return "aquaburst" end
		return s
	end

	local function getEquippedSkill(): string?
		local plot = findPlot()
		local id = plot and plot:GetAttribute("EquippedSkillId")
		if (not id or id == "") then id = hero:GetAttribute("EquippedSkillId") end
		return canonSkill(id)
	end

	local function getSkillLevel(id: string): number
		id = canonSkill(id)
		if not id or id == "" then return 0 end
		local plot = findPlot()
		local lv = plot and plot:GetAttribute("SkillLevel_"..id) or 0
		if (not lv or lv == 0) then lv = hero:GetAttribute("SkillLevel_"..id) or 0 end
		return lv
	end

	local skillCDEnds = { firebolt=0, quake=0, aquaburst=0 }
	local gcdEnds = 0

	local function canUseSkill(id: string): boolean
		id = canonSkill(id)
		if not id then return false end
		if getSkillLevel(id) <= 0 then return false end
		local now = time()
		return (now >= skillCDEnds[id]) and (now >= gcdEnds)
	end

	local function startCooldowns(id: string)
		id = canonSkill(id)
		local now = time()
		skillCDEnds[id] = now + (COOLDOWN[id] or 6)
		gcdEnds = now + GCD_SECONDS
	end

	-- ===== NEW: Shield absorb for incoming damage =====
	local conns = {}
	do
		local reenter = false
		local lastHealth = hum.Health
		table.insert(conns, hum.HealthChanged:Connect(function(newHealth)
			if reenter then return end
			local old = lastHealth
			lastHealth = newHealth
			if newHealth >= old then return end
			local incoming = old - newHealth
			if incoming <= 0 then return end

			local shield = hero:GetAttribute("ShieldHP") or 0
			if shield > 0 then
				local absorb = math.min(incoming, shield)
				hero:SetAttribute("ShieldHP", shield - absorb)

				reenter = true
				hum.Health = math.min(hum.MaxHealth, hum.Health + absorb)
				reenter = false
				lastHealth = hum.Health

				if (shield - absorb) <= 0 and RE_VFX then
					RE_VFX:FireAllClients({ kind = "aquabarrier_kill", who = hero })
				end
			end
		end))
	end

	-- ===== CASTS =====
	local function cast_firebolt(target: Instance, lv: number)
		if not target or lv <= 0 then return end
		local p = targetPos(target); if not p then return end
		faceTowards(hrp, p)
		hero:SetAttribute("CastTick", "firebolt@"..tostring(os.clock()))

		local bolt = Instance.new("Part")
		bolt.Size = Vector3.new(0.4,0.4,0.4)
		bolt.Shape = Enum.PartType.Ball
		bolt.CanCollide = false
		bolt.Anchored = true
		bolt.Color = Color3.fromRGB(255,120,60)
		bolt.Position = (hrp.Position + Vector3.new(0,2,0))
		bolt.Parent = workspace

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

		local forward = hrp.CFrame.LookVector
		local hits = getEnemiesInCone(hrp.Position, forward, QUAKE_RANGE, QUAKE_ANGLE)
		if #hits == 0 then return end

		local base = quakeDamage(lv) * quakeConeFrac(lv)
		for _, e in ipairs(hits) do
			applyDamage(e, base, Color3.fromRGB(200,170,120), true)
		end

		local ring = Instance.new("Part")
		ring.Anchored=true; ring.CanCollide=false; ring.Transparency=0.4
		ring.Color=Color3.fromRGB(230,210,160); ring.Size=Vector3.new(1,0.2,1)
		ring.CFrame=CFrame.new(hrp.Position + Vector3.new(0,0.2,0)); ring.Parent=workspace
		TweenService:Create(ring, TweenInfo.new(0.3), {Size=Vector3.new(QUAKE_RANGE*2,0.2,QUAKE_RANGE*2), Transparency=1}):Play()
		game:GetService("Debris"):AddItem(ring, 0.4)
	end

	local function aquaRingVFX(radius: number)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Color = Color3.fromRGB(120,200,255)
		p.Material = Enum.Material.Neon
		p.Transparency = 0.35
		p.CanCollide = false
		p.Anchored = true
		p.Size = Vector3.new(1,1,1)
		p.CFrame = hrp.CFrame
		p.Parent = workspace
		local grow = radius * 2
		local t0 = os.clock()
		local dur = 0.35
		local conn; conn = RunService.Heartbeat:Connect(function()
			if not p.Parent then if conn then conn:Disconnect() end return end
			local t = (os.clock() - t0) / dur
			if t >= 1 then p:Destroy(); if conn then conn:Disconnect() end return end
			local s = 1 + grow * t
			p.Size = Vector3.new(s, s, s)
			p.CFrame = hrp.CFrame
			p.Transparency = 0.35 + 0.55 * t
		end)
	end

	local function cast_aquaburst(lv: number)
		if lv <= 0 then return end
		hero:SetAttribute("CastTick", "aquaburst@"..tostring(os.clock()))
		applyHeal(hero, aquaHeal(lv))
		hero:SetAttribute("BarrierUntil", os.clock() + 2.0 + 0.5*lv)
		aquaRingVFX(10)
	end

	-- ===== MELEE =====
	local lastMelee = 0
	local function tryMelee(target: Instance): boolean
		local p = targetPos(target)
		if not p then return false end
		local dist = (p - hrp.Position).Magnitude
		if dist > ATTACK_RANGE then return false end
		if time() - lastMelee < SWING_COOLDOWN then return true end
		lastMelee = time()
		faceTowards(hrp, p)
		hero:SetAttribute("MeleeTick", os.clock())
		applyDamage(target, MELEE_DAMAGE, Color3.fromRGB(255,235,130), true)
		return true
	end

	-- Cleanup
	table.insert(conns, hero.Destroying:Connect(function()
		Brain.detach(hero)
	end))

	-- ===== MAIN LOOP =====
	local running = true
	ACTIVE[hero] = { conns = conns, hum = hum, hrp = hrp, running = running }

	task.spawn(function()
		while running and hero.Parent do
			task.wait(REPATH_EVERY)

			if hum.Health <= 0 then
				repeat task.wait(0.2) until hum.Health > 0 and hero.Parent
				lastMelee = 0
				skillCDEnds = { firebolt=0, quake=0, aquaburst=0 }
				gcdEnds = 0
			end

			local target   = pickTarget()
			local equipped = getEquippedSkill()

			if equipped == "aquaburst" and canUseSkill("aquaburst") then
				if hum.Health / math.max(1, hum.MaxHealth) <= AQUA_EMERGENCY_HP then
					cast_aquaburst(getSkillLevel("aquaburst"))
					startCooldowns("aquaburst")
					continue
				end
			end

			if target then
				if equipped == "quake" and canUseSkill("quake") then
					local foes = {}
					foes = foes or {}
					foes = (function()
						return (function() return foes end)()
					end)()
					local list = {}
					list = list or {}
					list = (function() return list end)()
					local hits = (function()
						return (function()
							return (function()
								return (function()
									return (function()
										return (function()
											return (function()
												return (function()
													return (function()
														return (function()
															return (function()
																return (function()
																	return (function()
																		return getEnemiesInCone(hrp.Position, hrp.CFrame.LookVector, QUAKE_RANGE, QUAKE_ANGLE)
																	end)()
																end)()
															end)()
														end)()
													end)()
												end)()
											end)()
										end)()
									end)()
								end)()
							end)()
						end)()
					end)()
					if #hits >= 2 then
						cast_quake(target, getSkillLevel("quake"))
						startCooldowns("quake")
						continue
					end
				end

				if equipped == "firebolt" and canUseSkill("firebolt") then
					local p = targetPos(target)
					if p and (p - hrp.Position).Magnitude <= 28 then
						cast_firebolt(target, getSkillLevel("firebolt"))
						startCooldowns("firebolt")
						continue
					end
				end

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
	ACTIVE[hero] = nil
end

return Brain
