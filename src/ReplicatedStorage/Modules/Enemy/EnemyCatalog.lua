-- ReplicatedStorage/Modules/Enemy/EnemyCatalog.lua
local Catalog = {
	Basic = {
		templatePath = "ServerStorage/EnemyTemplate",
		archetype = "melee",
		base = { hp = 100, dmg = 10, speed = 12, range = 6.0, cd = 0.8 },
		growth = { hp = 1.12, dmg = 1.09 },
		hipHeightOverride = 0.1,
	},
	Runner = {
		templatePath = "ServerStorage/EnemyTemplate",
		archetype = "runner",
		base = { hp = 90, dmg = 9, speed = 18, range = 6.5, cd = 0.9 },
		growth = { hp = 1.10, dmg = 1.07 },
		hipHeightOverride = 0.1,
	},
	Archer = {
		templatePath = "ServerStorage/EnemyTemplate",
		archetype = "ranged",
		base = { hp = 70, dmg = 12, speed = 10, range = 20, cd = 1.7 },
		growth = { hp = 1.10, dmg = 1.06 },
		projectile = { speed = 60, life = 2.5 },
		hipHeightOverride = 0.1,
	},
	MiniBasic = { ref = "Basic", hpMul = 5.0, dmgMul = 1.4, rank = "MiniBoss" },
}

local function resolve(id)
	local def = Catalog[id] or Catalog.Basic
	if def.ref then
		local base = resolve(def.ref)
		local out = table.clone(base)
		for k,v in pairs(def) do out[k] = v end
		if out.base and def.hpMul then
			out.base.hp = math.floor((out.base.hp or 100) * def.hpMul)
		end
		if out.base and def.dmgMul then
			out.base.dmg = math.floor((out.base.dmg or 10) * def.dmgMul)
		end
		return out
	end
	return def
end

function Catalog.get(id)
	return resolve(id or "Basic")
end

return Catalog
