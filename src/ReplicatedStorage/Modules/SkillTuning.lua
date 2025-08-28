-- SkillTuning.lua  (v1.2 — single source of truth)

local MAX = 5

-- All skill numbers live here
local Skills = {
	firebolt = {
		hit        = {30,40,50,60,75},
		range      = 46,
		cd         = 6,
		dotPctLv5  = 0.45,      -- 45% of hit over 4s
	},
	-- Quake back to a wide ring
	quakepulse = {
		hit           = {45,60,75,90,105},
		radius        = 10,
		cd            = 10,
		aftershockPct = 0.50,
		fracturePct   = 0.15,
		fractureDur   = 4.0,
	},

	-- Aqua becomes a 5s DoT aura around hero + shield (no double-self HoT)
	aquabarrier = {
		-- NEW DoT definition: TOTAL damage dealt over 5s (ticks below)
		dotTotal      = {22,30,38,48,60},
		dotTicks      = 5,       -- 1 tick/sec for 5s
		dotRadius     = 10,      -- same as QuakePulse radius

		duration      = 6,       -- shield lifetime
		cd            = 10,
		shield        = {50,65,80,95,110},

		-- Lv5 perk HoT (no more double-self)
		hotTotalLv5   = 50,
		hotTicks      = 5,
	},
}
	-- client knobs
	local CLIENT = {
		TICK               = 0.10,
		QUAKE_MIN_ENEMIES  = 2,
		HIT_TRIGGER_WINDOW = 1.0,
		AQUA_HP_THRESHOLD  = 0.75,
		SEND_GUARD         = 0.20,

		QUAKE_RADIUS = Skills.quakepulse.radius,
		FIRE_RANGE   = Skills.firebolt.range,
	}

-- Flat accessor
local function Stat(id, lvl)
	id = tostring(id or ""):lower()
	local L = math.clamp(lvl or 1, 1, MAX)
	local s = Skills[id]; if not s then return {} end

	if id == "firebolt" then
		return { damage = s.hit[L], range = s.range, cooldown = s.cd }

	elseif id == "aquabarrier" then
		return {
			damage   = s.dotTotal[L],   -- show total DoT over 5s
			radius   = s.dotRadius,
			duration = s.duration,
			cooldown = s.cd,
			shield   = (s.shield and s.shield[L]) or 0, -- <-- use L, not lv
		}

	elseif id == "quakepulse" then
		return { damage = s.hit[L], radius = s.radius, cooldown = s.cd }
	end

	return {}
end




	-- Legacy mirrors
	return {
		MAX_LEVEL = MAX,
		Skills    = Skills,
		FIRE_RANGE  = Skills.firebolt.range,
		QUAKE_RANGE = Skills.quakepulse.radius,
		AQUA_DURATION = Skills.aquabarrier.duration,
		CD = { firebolt=Skills.firebolt.cd, aquabarrier=Skills.aquabarrier.cd, quakepulse=Skills.quakepulse.cd },
		CLIENT = CLIENT, Client = CLIENT,
		Stat = Stat,
	}
