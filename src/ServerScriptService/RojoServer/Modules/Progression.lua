-- ServerScriptService/RojoServer/Modules/Progression.lua
local Progression = {}
local Data = require(game.ServerScriptService.RojoServer.Data.PlayerData)

function Progression.InitPlayer(player: Player)
  -- Do nothing except ensure data is loaded & mirrored once.
  Data.EnsureLoaded(player)
end

function Progression.AddXP(player: Player, amount: number)
  Data.AddXP(player, amount)
end

return Progression
