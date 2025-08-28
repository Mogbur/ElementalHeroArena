-- ReplicatedStorage/Combat.lua
local CollectionService = game:GetService("CollectionService")

local Combat = {}

-- ±25% triangle for skills
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

local function findEnemyModel(inst: Instance)
	if not inst then return nil end
	local model = inst:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Enemy") then
		return model
	end
	return nil
end

-- Apply to a Model (Humanoid), or fall back to a BasePart with Health attribute.
function Combat.ApplyDamage(player, target, baseDamage, attackElem)
	if not target then return false end

	-- Prefer enemy model with Humanoid
	local model = target:IsA("Model") and target or findEnemyModel(target)
	if model then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local targetElem = model:GetAttribute("Element") or "Neutral"
			local dmg = math.max(0, math.floor(baseDamage * elemMult(attackElem, targetElem)))
			hum:TakeDamage(dmg)
			model:SetAttribute("LastHitBy", player and player.UserId or 0)
			return (hum.Health - dmg) <= 0, dmg
		end
	end

	-- Fallback: raw part with custom Health attribute
	if target:IsA("BasePart") then
		local health = target:GetAttribute("Health")
		if health then
			local targetElem = target:GetAttribute("Element") or "Neutral"
			local dmg = math.max(0, math.floor(baseDamage * elemMult(attackElem, targetElem)))
			health -= dmg
			target:SetAttribute("Health", health)
			if health <= 0 then
				target:Destroy()
				return true, dmg
			end
			return false, dmg
		end
	end

	return false, 0
end

-- Radius AOE over enemy models
function Combat.ApplyAOE(player, centerPos: Vector3, radius, baseDamage, attackElem, rootSeconds)
	local parts = workspace:GetPartBoundsInRadius(centerPos, radius)
	local hitModels = {}
	for _, part in ipairs(parts) do
		local m = findEnemyModel(part)
		if m and not hitModels[m] then
			hitModels[m] = true
			Combat.ApplyDamage(player, m, baseDamage, attackElem)
			if rootSeconds and rootSeconds > 0 then
				m:SetAttribute("RootUntil", time() + rootSeconds)
			end
		end
	end
end

return Combat
