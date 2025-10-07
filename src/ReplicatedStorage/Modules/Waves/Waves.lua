local Waves = {
  BASE_ENEMIES = 3,
  BASE_HEALTH  = 100,
  BASE_DAMAGE  = 10,
  HEALTH_STEP  = 1.20,
  DAMAGE_STEP  = 1.10,
  COUNT_EVERY  = 2,
  MAX_COUNT    = 6,
  REWARD_MONEY = 10,
  REWARD_SEEDS = 1,
}

function Waves.get(waveIndex: number)
  local count = math.min(Waves.BASE_ENEMIES + math.floor((waveIndex-1)/Waves.COUNT_EVERY), Waves.MAX_COUNT)
  local healthM = Waves.HEALTH_STEP ^ (waveIndex-1)
  local dmgM    = Waves.DAMAGE_STEP   ^ (waveIndex-1)
  return {
    index = waveIndex, count = count,
    healthMul = healthM, damageMul = dmgM,
    rewardMoney = Waves.REWARD_MONEY * waveIndex,
    rewardSeeds = Waves.REWARD_SEEDS,
  }
end

-- hook up Composer if present
local Composer
pcall(function()
    Composer = require(script.Parent:FindFirstChild("Composer"))
end)

function Waves.build(args)
    if Composer and type(Composer.build) == "function" then
        return Composer.build(args)
    else
        local count = (args and args.count) or 3
        return { list = { {kind="Basic", n=count} } }
    end
end

return Waves
