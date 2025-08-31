-- ReplicatedStorage/Modules/Combat.lua
local CollectionService = game:GetService("CollectionService")

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
-- When pool hits 0 OR time is up, clears both and relies on client VFX to auto-despawn.
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
		-- still shield left after soaking
		m:SetAttribute("ShieldHP", shp - amount)
		return 0
	else
		-- broke the shield
		m:SetAttribute("ShieldHP", 0)
		m:SetAttribute("ShieldUntil", 0)
		return remain
	end
end

-- ==================== damage APIs ====================
function Combat.ApplyDamage(sourcePlayer, target, baseDamage, attackElem)
	if not target or not baseDamage or baseDamage <= 0 then return false, 0 end

	-- Allow part or model; prefer enemy model if a part was passed
	local model = target:IsA("Model") and target or findEnemyModel(target) or modelOf(target)
	local elemMultOut = 1.0

	-- Element reading (from model/part)
	local targetElem
	if model then
		targetElem = model:GetAttribute("Element") or "Neutral"
	elseif typeof(target) == "Instance" and target:IsA("BasePart") then
		targetElem = target:GetAttribute("Element") or "Neutral"
	else
		targetElem = "Neutral"
	end
	elemMultOut = elemMult(attackElem, targetElem)

	local dmg = math.max(0, math.floor(baseDamage * elemMultOut + 0.5))

	-- If the *target* has a humanoid, we apply humanoid damage (with shield-absorb first)
	if model then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			-- shield absorb (only if the target has a shield)
			local afterShield = absorbShield(model, dmg)
			if afterShield > 0 then
				hum:TakeDamage(afterShield)
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
			-- (rare) parts can also carry a shield (same rules)
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
			Combat.ApplyDamage(sourcePlayer, m, baseDamage, attackElem)
			if rootSeconds and rootSeconds > 0 then
				m:SetAttribute("RootUntil", os.clock() + rootSeconds)
			end
		end
	end
end

return Combat
