-- ReplicatedStorage/Modules/Enemy/Archetypes.lua
-- Adapter that loads the right per-archetype "brain", tolerating folder moves.
local RS = game:GetService("ReplicatedStorage")

local function enemyRoot()
	-- Prefer new Rojo path
	local mods = RS:FindFirstChild("Modules")
	if mods and mods:FindFirstChild("Enemy") then return mods.Enemy end
	-- Fallback to legacy ReplicatedStorage.Enemy
	return RS:WaitForChild("Enemy")
end

local EnemyFolder = enemyRoot()
local Root = EnemyFolder:FindFirstChild("Brains") or EnemyFolder:FindFirstChild("AI") or EnemyFolder

local Brains = {
	melee  = require(Root:WaitForChild("Melee")),
	runner = require(Root:WaitForChild("Runner")),
	ranged = require(Root:WaitForChild("Ranged")),
}

local A = {}

function A.attach(model, def)
	local brain = Brains[(def.archetype or "melee"):lower()]
	if not brain then return function() end end

	local cfg = {}
	if def.base then
		cfg.WalkSpeed   = def.base.speed
		cfg.AttackRange = def.base.range
		cfg.Cooldown    = def.base.cd
	end
	if def.projectile and (def.archetype == "ranged") then
		cfg.ProjectileSpeed = def.projectile.speed
		cfg.ProjectileLife  = def.projectile.life
	end

	return brain.start(model, cfg) or function() end
end

return A
