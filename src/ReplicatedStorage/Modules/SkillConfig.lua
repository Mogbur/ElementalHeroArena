-- SkillConfig.lua  (stats proxy to SkillTuning)
local SkillTuning = require(script.Parent:WaitForChild("SkillTuning"))

local cfg = {}

cfg.firebolt = {
	element="Fire", displayName="Firebolt",
	unlock={money=0, Fire=0, heroLevel=1},
	levelCost=function(_) return {money=0, Fire=0} end,
	maxLevel=5,
	stats = function(lvl)
		local s = T.Stat("firebolt", lvl)
		return {
			damage   = s.damage,
			range    = s.range,
			cooldown = s.cooldown,
		}
	end,
}

cfg.aquabarrier = {
	element="Water", displayName="AquaBarrier", aliases={"AquaBarrier","Watershield"},
	unlock={money=0, Water=0, heroLevel=1},
	levelCost=function(_) return {money=0, Water=0} end,
	maxLevel=5,
	stats = function(lvl)
		local s = T.Stat("aquabarrier", lvl)
		return {
			-- IMPORTANT: expose shield so the board can show it
			damage   = s.damage,          -- total DoT over 5s
			radius   = s.radius,
			duration = s.duration,
			cooldown = s.cooldown,
			shield   = s.shield or 0,     -- <<< this was missing
			-- UI hints (optional)
			triggerEnemyCount = 2,
			triggerRange      = 12,
			radiusVisual      = 10,
		}
	end,
}

cfg.quakepulse = {
	element="Earth", displayName="QuakePulse",
	unlock={money=0, Earth=0, heroLevel=1},
	levelCost=function(_) return {money=0, Earth=0} end,
	maxLevel=5,
	stats = function(lvl)
		local s = T.Stat("quakepulse", lvl)
		return {
			damage   = s.damage,
			radius   = s.radius,
			cooldown = s.cooldown,
		}
	end,
}

-- Legacy mirrors for any old code/saves
cfg.Firebolt    = cfg.firebolt
cfg.WaterShield = cfg.aquabarrier
cfg.QuakePulse  = cfg.quakepulse

return cfg
