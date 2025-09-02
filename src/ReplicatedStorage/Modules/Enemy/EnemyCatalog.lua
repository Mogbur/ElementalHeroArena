-- Only change the numbers below; structure unchanged
local Catalog = {
  Basic = {
    templatePath = "ServerStorage/EnemyTemplate",
    archetype = "melee",
    base   = { hp = 90, dmg = 8,  speed = 12, range = 6.0, cd = 1.2 }, -- cd slower
    growth = { hp = 1.10, dmg = 1.05 },
    hipHeightOverride = 0.1,
  },
  Runner = {
    templatePath = "ServerStorage/EnemyTemplate",
    archetype = "runner",
    base   = { hp = 85, dmg = 7,  speed = 18, range = 6.5, cd = 1.1 },
    growth = { hp = 1.08, dmg = 1.05 },
    hipHeightOverride = 0.1,
  },
  Archer = {
    templatePath = "ServerStorage/EnemyTemplate",
    archetype = "ranged",
    base   = { hp = 70, dmg = 10, speed = 10, range = 20, cd = 2.0 }, -- slower shots
    growth = { hp = 1.08, dmg = 1.05 },
    projectile = { speed = 70, life = 2.5 }, -- slightly slower bolts
    hipHeightOverride = 0.1,
  },
  MiniBasic = { ref = "Basic", hpMul = 4.0, dmgMul = 1.3, rank = "MiniBoss" },
}
