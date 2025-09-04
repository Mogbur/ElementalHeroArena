return {
  SwordShield = {
    hpMul     = 1.10,   -- +10% Max HP
    atkMul    = 0.95,   -- −5% ATK (applied to basic + skills if you want)
    spdMul    = 1.00,   -- attack speed
    guardDR   = 0.50,   -- next hit −50%
    guardCD   = 6.0,   -- every 6s
  },
  Bow = {
    hpMul     = 0.85,   -- −15% Max HP
    atkMul    = 1.00,
    spdMul    = 1.20,   -- +20% attack speed
    forcedCritNth   = 6,    -- every 6th basic
    forcedCritBonus = 0.40, -- +40% damage on that basic
  },
  Mace = {
    hpMul     = 1.00,
    atkMul    = 1.15,   -- +15% ATK
    spdMul    = 0.80,   -- −20% attack speed
    stunICD   = 1.0,    -- per-target internal cooldown
    stunDur   = 0.60,   -- stun duration (seconds)
    -- stun chance comes from Mastery ranks
  },
}
