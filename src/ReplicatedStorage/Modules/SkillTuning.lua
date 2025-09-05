-- ReplicatedStorage/Modules/SkillTuning.lua (v1.2)
local MAX = 5

local Skills = {
	firebolt = { hit = {30,40,50,60,75}, range = 90, cd = 2.2, dotPctLv5 = 0.45 },
	quakepulse = { hit = {45,60,75,90,105}, radius = 10, cd = 6.0, aftershockPct = 0.50, fracturePct = 0.15, fractureDur = 4.0 },
	aquabarrier = {
		dotTotal = {22,30,38,48,60},
		dotTicks = 5,          -- 1/s for 5s
		dotRadius = 10,
		duration = 6,
		cd = 10,
		shield = {65,85,100,135,165},
		hotTotalLv5 = 50,
		hotTicks = 5,
	},
}
-- NEW: top-level knobs so Bow basic and Firebolt can differ
local RANGES = {
	FIREBOLT = Skills.firebolt.range, -- skill cast gate
	BOW_BASIC = 36,                   -- bow “basic attack” gate (doesn’t change stand distance while stopAt=18)
}

local CLIENT = {
	TICK = 0.10,
	QUAKE_MIN_ENEMIES = 2,
	HIT_TRIGGER_WINDOW = 1.0,
	AQUA_HP_THRESHOLD = 0.75,
	SEND_GUARD = 0.20,
	QUAKE_RADIUS = Skills.quakepulse.radius,
	FIRE_RANGE = Skills.firebolt.range,
}

local function Stat(id, lvl)
	id = tostring(id or ""):lower()
	local L = math.clamp(lvl or 1, 1, MAX)
	local s = Skills[id]; if not s then return {} end
	if id == "firebolt" then
		return { damage = s.hit[L], range = s.range, cooldown = s.cd }
	elseif id == "aquabarrier" then
		return {
			damage = s.dotTotal[L],
			radius = s.dotRadius,
			duration = s.duration,
			cooldown = s.cd,
			shield = (s.shield and s.shield[L]) or 0,
		}
	elseif id == "quakepulse" then
		return { damage = s.hit[L], radius = s.radius, cooldown = s.cd }
	end
	return {}
end

return {
	MAX_LEVEL = MAX,
	Skills = Skills,
	-- NEW exports
	FIREBOLT_RANGE = RANGES.FIREBOLT,
	BOW_BASIC_RANGE = RANGES.BOW_BASIC,
	-- Back-compat fields other modules may still read
	FIRE_RANGE = RANGES.FIREBOLT,
	QUAKE_RANGE = Skills.quakepulse.radius,
	AQUA_DURATION = Skills.aquabarrier.duration,
	CD = {
		firebolt=Skills.firebolt.cd,
		aquabarrier=Skills.aquabarrier.cd,
		quakepulse=Skills.quakepulse.cd
	},
	-- NEW: global cooldown used by HeroAI (seconds)
	GLOBAL_CD = 3,
	
	CLIENT = CLIENT,
	Client = CLIENT,
	Stat = Stat,
}
