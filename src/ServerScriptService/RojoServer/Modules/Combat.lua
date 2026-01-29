-- ServerScriptService/Modules/Combat.lua
print(("[Combat] loaded: %s"):format(script:GetFullName()))
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

-- near other requires
local PlayerData = require(game.ServerScriptService.RojoServer.Data.PlayerData)
local WeaponStyles = require(RS.Modules.WeaponStyles)
local StyleMastery = require(RS.Modules.StyleMastery)
local SSS = game:GetService("ServerScriptService")
local DropService = require(SSS.RojoServer.Modules.DropService)
local Remotes = RS:WaitForChild("Remotes")
local RE_CVFX = Remotes:FindFirstChild("CombatVFX")

local Combat = {}

-- ==================== elements ====================
local function elemMult(attackElem, targetElem)
	attackElem = attackElem or "Neutral"
	targetElem = targetElem or "Neutral"
	if attackElem == "Fire" then
		if targetElem == "Earth" then return 1.25 elseif targetElem == "Water" then return 0.75 end
	elseif attackElem == "Water" then
		if targetElem == "Fire" then return 1.25 elseif targetElem == "Earth" then return 0.75 end
	elseif attackElem == "Earth" then
		if targetElem == "Water" then return 1.25 elseif targetElem == "Fire" then return 0.75 end
	end
	return 1.0
end

-- small helpers
local function modelOf(x)
	if typeof(x) == "Instance" then
		if x:IsA("Model") then return x end
		if x:IsA("BasePart") then return x.Parent end
	end
	return nil
end

local function findEnemyModel(inst: Instance)
	if not inst then return nil end
	local m = inst:FindFirstAncestorOfClass("Model")
	if m and (CollectionService:HasTag(m, "Enemy") or m:GetAttribute("IsEnemy") or m.Name == "Enemy") then
		return m
	end
	return nil
end

local function plotByOwner(userId)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _,p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and (p:GetAttribute("OwnerUserId") or 0) == userId then
			return p
		end
	end
end

local function heroModelForPlayer(plr: Player)
	if not plr then return nil end

	local plot = plotByOwner(plr.UserId)
	if plot then
		local hero = plot:FindFirstChild("Hero", true)
		if hero and hero:IsA("Model") then
			-- OPTIONAL DEBUG:
			print("[Combat] heroModelForPlayer ->", plr.Name, "HERO:", hero:GetFullName(),
			      "fallbackChar=", plr.Character and plr.Character:GetFullName())
			return hero
		end
	end

	-- OPTIONAL DEBUG:
	print("[Combat] heroModelForPlayer ->", plr.Name, "HERO: nil",
	      "fallbackChar=", plr.Character and plr.Character:GetFullName())
	return plr.Character
end

-- segment id from a plot's CurrentWave
local function segId(plot: Instance)
	local w = tonumber(plot and plot:GetAttribute("CurrentWave")) or 1
	return math.floor((w - 1) / 5)
end

local function plotOf(inst: Instance)
	local cur = inst
	while cur do
		if cur:IsA("Model") and cur:GetAttribute("OwnerUserId") ~= nil then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- ==================== shielding ====================
-- Uses attributes:
--   ShieldHP (number)        - remaining pool
--   ShieldExpireAt (os.clock()) - absolute expiry time (seconds)
local function absorbShield(target, amount)
	local m = modelOf(target)
	if not (m and amount and amount > 0) then return amount end

	local shp = tonumber(m:GetAttribute("ShieldHP")) or 0
	if shp <= 0 then return amount end

	-- expire by time as well
	local untilT = tonumber(m:GetAttribute("ShieldExpireAt")) or 0
	if untilT > 0 and os.clock() >= untilT then
		m:SetAttribute("ShieldHP", 0)
		m:SetAttribute("ShieldExpireAt", 0)
		return amount
	end

	-- soak damage from pool
	local remain = amount - shp
	if remain <= 0 then
		m:SetAttribute("ShieldHP", shp - amount)
		return 0
	else
		m:SetAttribute("ShieldHP", 0)
		m:SetAttribute("ShieldExpireAt", 0)
		return remain
	end
end

-- === Style runtime (tiny, local) ===
local bowCount = setmetatable({}, {__mode="k"})     -- [Player] = int
local guardT   = setmetatable({}, {__mode="k"})     -- [Player] = os.clock()

-- Bow surge VFX debounce (prevents double-fire if ApplyDamage gets called twice)
local lastSurgeFxAt = setmetatable({}, { __mode = "k" }) -- [Model] = os.clock()

local function styleIdFor(plr: Player)
	local main = (plr:GetAttribute("WeaponMain") or "Sword"):lower()
	local off  = (plr:GetAttribute("WeaponOff")  or ""):lower()
	if main == "bow" then return "Bow"
	elseif main == "mace" then return "Mace"
	elseif main == "sword" and off == "shield" then return "SwordShield"
	else return plr:GetAttribute("CurrentStyle") or "SwordShield" end
end

local function snap(plr: Player)
	local id = styleIdFor(plr)
	local W  = WeaponStyles[id] or {}
	local xp = plr:GetAttribute("StyleXP_"..id) or 0
	local B  = StyleMastery.bonuses(id, xp) or {}
	return {
		id = id,
		atk = W.atkMul or 1, spd = W.spdMul or 1, hp = W.hpMul or 1,
		-- S&S
		guardDR = W.guardDR or 0.5, guardCD = W.guardCD or 6, drFlat = B.drFlat or 0,
		-- Bow
		nth = W.forcedCritNth or 6, bonus = W.forcedCritBonus or 0.4, critMul = B.critDmgMul or 1, critChanceAdd = B.critChanceAdd or 0,
		-- Mace
		stunChance = B.stunChance or 0, stunDur = W.stunDur or 0.6,
	}
end
-- === Level scaling (global) ===
local function levelDmgMul(plr: Player)
	local lvl = (plr and plr:GetAttribute("Level")) or 1
	return 1 + 0.04 * math.max(0, lvl - 1)
end
-- Flux reward scales by wave bracket and rank
local function waveTier(w)
	if w >= 30 then return 4
	elseif w >= 20 then return 3
	elseif w >= 10 then return 2
	else return 1
	end
end

local function fluxFor(rank, wave)
	-- tweak these tables any time
	local mini = { 8, 14, 22, 35 } -- miniboss flux per tier
	local boss = { 18, 30, 46, 70 } -- boss flux per tier
	local t = waveTier(wave)
	if rank == "Boss" then return boss[t] else return mini[t] end
end

-- === Style mastery helpers (global) ===
local function styleIdFrom(plr: Player)
	if not plr then return "SwordShield" end
	local main = string.lower(plr:GetAttribute("WeaponMain") or "sword")
	if main == "mace" then return "Mace"
	elseif main == "bow" then return "Bow"
	else return "SwordShield" end
end

local function addStyleXP(plr: Player, amount: number)
	if not plr or (amount or 0) <= 0 then return end
	local style = styleIdFrom(plr)
	pcall(function() PlayerData.AddStyleXP(plr, style, amount) end)
end

-- Award only for MiniBoss / Boss kills; amounts are intentionally generous
local function awardKillStyleXP(plr: Player, victimModel: Model)
	if not (plr and victimModel) then return end
	local rank = tostring(victimModel:GetAttribute("Rank") or "")
	if rank == "" then return end
	local wave = tonumber(victimModel:GetAttribute("Wave")) or 1
	if rank == "MiniBoss" then
		addStyleXP(plr, 80 + 4 * wave)     -- tweak to taste
	elseif rank == "Boss" then
		addStyleXP(plr, 180 + 6 * wave)    -- tweak to taste
	end
end

local function outgoingFromStyle(attacker: Player, baseDamage: number, isBasic: boolean)
	if not attacker then return baseDamage, {} end
	local S = snap(attacker)

	-- Only basics get offensive style mods. Skills/spells pass isBasic=false.
	local mul = 1.0
	local flags = { style = S.id, forcedCrit = false, critDmgMul = 1, stun = false, stunDur = 0 }

	if isBasic then
		-- base damage multiplier from style
		mul *= (S.atk or 1)

		-- Bow: every Nth BASIC is a forced crit (+bonus damage and extra crit multiplier from mastery)
		if S.id == "Bow" then
			bowCount[attacker] = (bowCount[attacker] or 0) + 1
			if (bowCount[attacker] % (S.nth or 6)) == 0 then
				flags.forcedCrit = true
				mul *= (1 + (S.bonus or 0))
				flags.critDmgMul = S.critMul or 1
				print("[BowDbg] forced shot", bowCount[attacker], "bonus", S.bonus, "critMul", flags.critDmgMul)
			end
		end

		-- Mace: BASIC hits can stun (chance from mastery)
		if S.id == "Mace" and math.random() < (S.stunChance or 0) then
			flags.stun = true
			flags.stunDur = S.stunDur or 0.6
		end
	end

	return baseDamage * mul, flags
end

local function incomingFromStyle(targetPlayer: Player, damage: number)
	if not targetPlayer then return damage end
	local S = snap(targetPlayer)

	-- Passive DR from mastery
	damage *= (1 - (S.drFlat or 0))

	-- S&S guard: every guardCD seconds, reduce the next hit by guardDR
	if S.id == "SwordShield" then
		local last = guardT[targetPlayer] or (os.clock() - 999)
		if (os.clock() - last) >= S.guardCD then
			guardT[targetPlayer] = os.clock()
			damage *= (1 - S.guardDR)
			-- VFX: spark when the guard is consumed
			local Remotes = RS:WaitForChild("Remotes")
			local RE = Remotes:FindFirstChild("CombatVFX")
			if RE and targetPlayer then
				local whoModel = heroModelForPlayer(targetPlayer) -- should be plot hero
				if whoModel then
					RE:FireAllClients({ kind = "shield_block", who = whoModel })
				end
			end
		end
	end
	return damage
end

-- ==================== damage APIs ====================
function Combat.ApplyDamage(sourcePlayer, target, baseDamage, attackElem, isBasic)
	if not target or not baseDamage or baseDamage <= 0 then
		return false, 0
	end

	-- Prefer an enemy/hero model; accept parts too
	local model = target:IsA("Model") and target or findEnemyModel(target) or modelOf(target)

	-- Outgoing damage from style...
	local outDmg, flags = outgoingFromStyle(sourcePlayer, baseDamage or 0, isBasic == true)

	-- Identify source plot once; used by ATK core, Blessing, etc.
	local srcPlot = nil
	if sourcePlayer then
		srcPlot = sourcePlayer.Character and plotOf(sourcePlayer.Character) or nil
		if not srcPlot then
			srcPlot = plotByOwner(sourcePlayer.UserId)
		end
	end

	-- Blessing rider: if caller didn't specify an element, default to the active Blessing for this segment
	do
		if not attackElem or attackElem == "Neutral" then
			if srcPlot then
				local w = tonumber(srcPlot:GetAttribute("CurrentWave")) or 1
				local curSeg = (w - 1) // 5
				local bElem  = srcPlot:GetAttribute("BlessingElem")
				local bSeg   = tonumber(srcPlot:GetAttribute("BlessingExpiresSegId")) or -999
				if bElem and bSeg == curSeg then
					attackElem = bElem
				end
			end
		end
	end

	-- >>> ATK core and Overcharge (fixed)
	do
		if srcPlot then
			-- 1) Core ATK (+8% per tier)
			if (srcPlot:GetAttribute("CoreId") == "ATK") then
				local t = tonumber(srcPlot:GetAttribute("CoreTier")) or 0
				outDmg = outDmg * (1 + 0.08 * t)
			end
			-- 2) Overcharge: segment-scoped % damage
			local ocPct  = tonumber(srcPlot:GetAttribute("Util_OverchargePct")) or 0
			local ocSeg  = tonumber(srcPlot:GetAttribute("UtilExpiresSegId")) or -1
			if ocPct > 0 and ocSeg == segId(srcPlot) then
				outDmg = outDmg * (1 + ocPct / 100)
			end
		end
	end
	-- <<< ATK core and Overcharge
	-- === Level: outgoing damage scaling ===
	outDmg = outDmg * levelDmgMul(sourcePlayer)
	-- === Global crits (BASICS ONLY) ===
	local didCrit = false
	if isBasic == true then
		do
			local cc, cm = 0, 2.0
			if srcPlot then
				cc = tonumber(srcPlot:GetAttribute("CritChance")) or 0
				cm = tonumber(srcPlot:GetAttribute("CritMult"))  or 2.0
			elseif sourcePlayer then
				cc = tonumber(sourcePlayer:GetAttribute("CritChance")) or 0
				cm = tonumber(sourcePlayer:GetAttribute("CritMult"))  or 2.0
			end

			-- add Bow mastery crit chance (0 for other styles)
			local addCC = 0
			if sourcePlayer then
				local Ssrc = snap(sourcePlayer)
				addCC = tonumber(Ssrc.critChanceAdd) or 0
			end
			local chance = math.clamp(cc + addCC, 0, 1)

			if chance > 0 and math.random() < chance then
				didCrit = true
				outDmg = math.floor(outDmg * cm + 0.5)
			end
		end
	end

	-- ===== spawn-guard / friendly fire / mute =====
	if model then
		-- hard mute during landing / guard
		if tonumber(model:GetAttribute("DamageMute")) == 1 then
			return false, 0
		end
		local now        = os.clock()
		local inv        = tonumber(model:GetAttribute("InvulnUntil"))     or 0
		local spawnGuard = tonumber(model:GetAttribute("SpawnGuardUntil")) or 0
		if now < math.max(inv, spawnGuard) then
			return false, 0
		end

		-- block friendly fire on your own hero
		local targetOwner = tonumber(model:GetAttribute("OwnerUserId")) or 0
		local srcOwner    = (sourcePlayer and sourcePlayer.UserId) or 0
		local isHero      = (model:GetAttribute("IsHero") == true)
			or (Players:GetPlayerFromCharacter(model) ~= nil)
		if isHero and srcOwner ~= 0 and targetOwner ~= 0 and srcOwner == targetOwner then
			return false, 0
		end
	end
	-- ==============================================

	-- element multiplier
	local targetElem = "Neutral"
	if model then
		targetElem = model:GetAttribute("Element") or "Neutral"
	elseif typeof(target) == "Instance" and target:IsA("BasePart") then
		targetElem = target:GetAttribute("Element") or "Neutral"
	end
	local elemMultOut = elemMult(attackElem, targetElem)

	-- final dmg after elements
	local dmg = math.max(0, math.floor(outDmg * elemMultOut + 0.5))
		-- Dev stats: track last hit numbers (includes core/OC/level/crit/forced)
	if sourcePlayer then
		sourcePlayer:SetAttribute("Dbg_LastOutDmg", math.floor(outDmg + 0.5)) -- before element mult
		sourcePlayer:SetAttribute("Dbg_LastFinalDmg", dmg)                    -- after element mult, before shields
		sourcePlayer:SetAttribute("Dbg_LastIsBasic", isBasic == true and 1 or 0)
		sourcePlayer:SetAttribute("Dbg_LastElem", tostring(attackElem or "Neutral"))
	end


	-- Humanoid target path (includes incoming style DR, shields, crit-dmg multiplier, stun)
	if model then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			-- target player's incoming reductions (Sword&Shield guard DR etc.)
			local targetPlayer = Players:GetPlayerFromCharacter(model)
			if not targetPlayer and model:IsA("Model") and (model:GetAttribute("IsHero") == true) then
				local ownerId = tonumber(model:GetAttribute("OwnerUserId")) or 0
				if ownerId > 0 then
					targetPlayer = Players:GetPlayerByUserId(ownerId)
				end
			end
			if targetPlayer then
				dmg = incomingFromStyle(targetPlayer, dmg)
			end

			-- shield absorb (ShieldHP/ShieldExpireAt attrs)
			local afterShield = absorbShield(model, dmg)

			-- forced-crit extra crit damage (Bow cadence mastery)
			if flags.forcedCrit and (flags.critDmgMul or 1) > 1 then
				afterShield = math.floor(afterShield * flags.critDmgMul + 0.5)
			end

			-- apply damage
			if afterShield > 0 then
				model:SetAttribute("LastHitBy", sourcePlayer and sourcePlayer.UserId or -1)
				model:SetAttribute("LastCombatDamageAt", os.clock())
				hum:TakeDamage(afterShield)

				-- Bow surge impact ONLY when hit actually landed (and don't double-fire)
				if flags.forcedCrit and RE_CVFX then
					local now = os.clock()
					local last = lastSurgeFxAt[model] or 0
					if (now - last) > 0.05 then -- 50ms debounce
						lastSurgeFxAt[model] = now
						local rp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
						if rp then
							RE_CVFX:FireAllClients({ kind = "bow_surge_hit", pos = rp.Position })
						end
					end
				end
			end

			-- Optional: Mace stun (authoritative here)
			if flags.stun and afterShield > 0 then
				local old = hum.WalkSpeed
				hum.WalkSpeed = 0

				-- VFX/SFX ping (ring + glonk) for clients
				local rp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				local RE = RS:WaitForChild("Remotes"):FindFirstChild("CombatVFX")
				if RE and rp then
					RE:FireAllClients({ kind = "mace_stun", pos = rp.Position })
				end

				-- (optional) set debuff window attrs for HUD
				local nowT = time()
				model:SetAttribute("StunStartAt", nowT)
				model:SetAttribute("StunDuration", flags.stunDur or 0.6)
				model:SetAttribute("StunnedUntil", nowT + (flags.stunDur or 0.6))

				task.delay(flags.stunDur or 0.6, function()
					if hum.Parent and hum.Health > 0 then
						hum.WalkSpeed = old
					end
					-- clear if not refreshed
					local untilT = tonumber(model:GetAttribute("StunnedUntil")) or 0
					if time() >= untilT - 0.01 then
						model:SetAttribute("StunnedUntil", 0)
						model:SetAttribute("StunDuration", 0)
						model:SetAttribute("StunStartAt", 0)
					end
				end)
			end

			local dead = hum.Health <= 0
			if dead then
				-- Only MiniBoss/Boss drop loot; Essence chance scales by wave bracket
				local rank = tostring(model:GetAttribute("Rank") or "")
				if rank ~= "" and sourcePlayer then
					-- Choose element: Blessing > LastElement > random F/W/E
					local function validElem(e) return e == "Fire" or e == "Water" or e == "Earth" end
					local elem
					if srcPlot then
						local w   = tonumber(srcPlot:GetAttribute("CurrentWave")) or 1
						local seg = (w - 1) // 5
						local bEl = srcPlot:GetAttribute("BlessingElem")
						local bOk = (bEl and (tonumber(srcPlot:GetAttribute("BlessingExpiresSegId")) or -1) == seg and validElem(bEl))
						if bOk then
							elem = tostring(bEl)
						else
							local last = tostring(srcPlot:GetAttribute("LastElement"))
							if validElem(last) then elem = last end
						end
					end
					if not elem then
						local pool = {"Fire","Water","Earth"}
						elem = pool[math.random(1,#pool)]
					end

					-- Wave-scaled essence chance p: 1–9:15%, 10–19:25%, 20–29:40%, 30+:60%
					local wave = tonumber(model:GetAttribute("Wave")) or 1
					local function chanceFor(w)
						if w >= 30 then return 0.60
						elseif w >= 20 then return 0.40
						elseif w >= 10 then return 0.25
						else return 0.15 end
					end
					local p = chanceFor(wave)

					-- Essence amount (same rules you had)
					local give = 0
					if rank == "MiniBoss" then
						if math.random() < p then give = 1 end
					elseif rank == "Boss" then
						give = 1
						if math.random() < p then give += 1 end
					end

					-- >>> Flux reward (always for miniboss/boss, scaled by wave)
					local fluxAmt = fluxFor(rank, wave)

					-- Build the payload; split into multiple orbs for feel
					local split = (rank == "Boss") and 3 or 2
					local payload = { flux = fluxAmt }
					if give > 0 then
						payload.essence = { [elem] = give }
					end

					-- Spawn orbs at the dead enemy; home to the killer only
					DropService.SpawnLootFrom(model, sourcePlayer, payload, split)

				else
					-- OPTIONAL: normal enemies get a small flat Flux drip
					if sourcePlayer then
						local wave = tonumber(model:GetAttribute("Wave")) or 1
						local small = ({2,3,4,6})[waveTier(wave)]  -- tweak to taste
						if small > 0 then
							DropService.SpawnLootFrom(model, sourcePlayer, { flux = small }, 1)
						end
					end
				end

				-- keep your existing style XP award
				awardKillStyleXP(sourcePlayer, model)
			end
			return dead, (afterShield > 0) and afterShield or 0
		end
	end

	-- Generic destructibles (BasePart with Health attribute)
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		local health = target:GetAttribute("Health")
		if health then
			local afterShield = absorbShield(target, dmg)
			if afterShield > 0 then
				health -= afterShield
				target:SetAttribute("Health", health)
			end
			if (target:GetAttribute("Health") or 0) <= 0 then
				target:Destroy()
				return true, math.max(0, afterShield)
			end
			return false, math.max(0, afterShield)
		end
	end

	return false, 0
end

function Combat.ApplyAOE(sourcePlayer, centerPos: Vector3, radius, baseDamage, attackElem, rootSeconds)
	if not (centerPos and radius and baseDamage) then return end
	local parts = workspace:GetPartBoundsInRadius(centerPos, radius)
	local hitModels = {}
	for _, part in ipairs(parts) do
		local m = findEnemyModel(part)
		if m and not hitModels[m] then
			hitModels[m] = true
			Combat.ApplyDamage(sourcePlayer, m, baseDamage, attackElem, false)
			if rootSeconds and rootSeconds > 0 then
				m:SetAttribute("RootUntil", os.clock() + rootSeconds)
			end
		end
	end
end

return Combat
