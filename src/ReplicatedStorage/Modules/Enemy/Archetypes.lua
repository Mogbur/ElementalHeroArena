local RS = game:GetService("ReplicatedStorage")
local EnemyFolder = RS:WaitForChild("Enemy")
local Root = EnemyFolder:FindFirstChild("Brains") or EnemyFolder:FindFirstChild("AI") or EnemyFolder

local Brains = {
	melee  = require(Root:WaitForChild("Melee")),
	runner = require(Root:WaitForChild("Runner")),
	ranged = require(Root:WaitForChild("Ranged")),
}


local A = {}

-- Attaches the right brain to a model. Returns a stop() no-op for symmetry.
function A.attach(model, def)
	local brain = Brains[def.archetype or "melee"]
	if not brain then return function() end end

	local cfg = {}
	if def.base then
		cfg.WalkSpeed   = def.base.speed
		cfg.AttackRange = def.base.range
		cfg.Cooldown    = def.base.cd
	end
	if def.projectile and def.archetype == "ranged" then
		cfg.ProjectileSpeed = def.projectile.speed
		cfg.ProjectileLife  = def.projectile.life
	end

	return brain.start(model, cfg) or function() end
end

return A
