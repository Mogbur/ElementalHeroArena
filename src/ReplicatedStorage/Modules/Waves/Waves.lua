-- ReplicatedStorage/Waves/Waves.lua
local Waves = {
	-- Tuning targets (quick knobs)
	BASE_ENEMIES   = 3,     -- start per wave
	BASE_HEALTH    = 100,   -- EnemyTemplate default HP you built to
	BASE_DAMAGE    = 10,    -- if/when enemies attack
	HEALTH_STEP    = 1.20,  -- +20% per wave
	DAMAGE_STEP    = 1.10,  -- +10% per wave
	COUNT_EVERY    = 2,     -- +1 enemy every 2 waves
	MAX_COUNT      = 6,

	-- test rewards
	REWARD_MONEY   = 10,    -- * waveIndex
	REWARD_SEEDS   = 1,     -- flat per wave for now
}

function Waves.get(waveIndex: number)
	local count   = math.min(Waves.BASE_ENEMIES + math.floor((waveIndex-1)/Waves.COUNT_EVERY), Waves.MAX_COUNT)
	local healthM = Waves.HEALTH_STEP ^ (waveIndex-1)
	local dmgM    = Waves.DAMAGE_STEP  ^ (waveIndex-1)
	return {
		index     = waveIndex,
		count     = count,
		healthMul = healthM,
		damageMul = dmgM,
		rewardMoney = Waves.REWARD_MONEY * waveIndex,
		rewardSeeds = Waves.REWARD_SEEDS,
	}
end

return Waves
