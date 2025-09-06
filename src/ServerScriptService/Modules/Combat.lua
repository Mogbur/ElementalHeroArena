-- ServerScriptService/Modules/Combat.lua
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local WeaponStyles = require(RS.Modules.WeaponStyles)
local StyleMastery = require(RS.Modules.StyleMastery)

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

-- ==================== shielding ====================
-- Uses attributes:
--   ShieldHP (number)        - remaining pool
--   ShieldUntil (os.clock()) - absolute expiry time (seconds)
local function absorbShield(target, amount)
	local m = modelOf(target)
	if not (m and amount and amount > 0) then return amount end

	local shp = tonumber(m:GetAttribute("ShieldHP")) or 0
	if shp <= 0 then return amount end

	-- expire by time as well
	local untilT = tonumber(m:GetAttribute("ShieldUntil")) or 0
	if untilT > 0 and os.clock() >= untilT then
		m:SetAttribute("ShieldHP", 0)
		m:SetAttribute("ShieldUntil", 0)
		return amount
	end

	-- soak damage from pool
	local remain = amount - shp
	if remain <= 0 then
		m:SetAttribute("ShieldHP", shp - amount)
		return 0
	else
		m:SetAttribute("ShieldHP", 0)
		m:SetAttribute("ShieldUntil", 0)
		return remain
	end
end

-- === Style runtime (tiny, local) ===
local bowCount = setmetatable({}, {__mode="k"})     -- [Player] = int
local guardT   = setmetatable({}, {__mode="k"})     -- [Player] = os.clock()

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
		nth = W.forcedCritNth or 6, bonus = W.forcedCritBonus or 0.4, critMul = B.critDmgMul or 1,
		-- Mace
		stunChance = B.stunChance or 0, stunDur = W.stunDur or 0.6,
	}
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
			if bowCount[attacker] % (S.nth or 6) == 0 then
				flags.forcedCrit = true
				mul *= (1 + (S.bonus or 0))
				flags.critDmgMul = S.critMul or 1
			end
		-- Mace: BASIC hits can stun (chance from mastery)
		elseif S.id == "Mace" and isBasic and math.random() < (S.stunChance or 0) then
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
		end
	end
	return damage
end

-- ==================== damage APIs ====================
function Combat.ApplyDamage(sourcePlayer, target, baseDamage, attackElem, isBasic)
	-- style: outgoing first (attacker)
	local outDmg, flags = outgoingFromStyle(sourcePlayer, baseDamage or 0, isBasic == true)
	if not target or not baseDamage or baseDamage <= 0 then return false, 0 end

	-- Allow part or model; prefer enemy model if a part was passed
	local model = target:IsA("Model") and target or findEnemyModel(target) or modelOf(target)
	
	-- >>> NEW: block same-owner damage + spawn/invuln guard
	if model then
		local now        = os.clock()
		local inv        = tonumber(model:GetAttribute("InvulnUntil")) or 0
		local spawnGuard = tonumber(model:GetAttribute("SpawnGuardUntil")) or 0
		if now < math.max(inv, spawnGuard) then
			-- During the guard window, ignore all incoming damage.
			return false, 0
		end

		-- Friendly-fire: don't let the same owner damage themselves (hero vs their own tickers/AOE)
		local targetOwner = tonumber(model:GetAttribute("OwnerUserId")) or 0
		local srcOwner    = (sourcePlayer and sourcePlayer.UserId) or 0
		if srcOwner ~= 0 and targetOwner ~= 0 and srcOwner == targetOwner then
			return false, 0
		end
	end
	-- <<< NEW


	-- element multiplier
	local targetElem = "Neutral"
	if model then
		targetElem = model:GetAttribute("Element") or "Neutral"
	elseif typeof(target) == "Instance" and target:IsA("BasePart") then
		targetElem = target:GetAttribute("Element") or "Neutral"
	end
	local elemMultOut = elemMult(attackElem, targetElem)

	-- damage after elements
	local dmg = math.max(0, math.floor(outDmg * elemMultOut + 0.5))

	-- If the *target* has a humanoid, apply humanoid damage (with incoming reductions + shield + crit)
	if model then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			-- incoming reductions (only apply if it's a Player character)
			-- resolve player owner for "Hero" models too
			local targetPlayer = Players:GetPlayerFromCharacter(model)
			if not targetPlayer and model and model:IsA("Model") then
				local ownerId = tonumber(model:GetAttribute("OwnerUserId")) or 0
				if ownerId > 0 then
					targetPlayer = Players:GetPlayerByUserId(ownerId)
				end
			end
			dmg = incomingFromStyle(targetPlayer, dmg)

			-- shield absorb (attributes on target)
			local afterShield = absorbShield(model, dmg)

			-- forced-crit extra crit damage (bow cadence)
			if flags.forcedCrit and (flags.critDmgMul or 1) > 1 then
				afterShield = math.floor(afterShield * flags.critDmgMul + 0.5)
			end

			if afterShield > 0 then
				hum:TakeDamage(afterShield)
			end

			-- optional: mace stun (simple WalkSpeed zero)
			if flags.stun and afterShield > 0 then
				local old = hum.WalkSpeed
				hum.WalkSpeed = 0
				task.delay(flags.stunDur or 0.6, function()
					if hum.Parent and hum.Health > 0 then
						hum.WalkSpeed = old
					end
				end)
			end

			model:SetAttribute("LastHitBy", sourcePlayer and sourcePlayer.UserId or 0)
			local dead = hum.Health <= 0
			return dead, (afterShield > 0) and afterShield or 0
		end
	end

	-- Generic destructible parts with custom "Health" attribute
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
