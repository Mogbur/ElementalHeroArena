local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local Data = require(SSS.RojoServer.Data.PlayerData)

Players.PlayerAdded:Connect(function(plr)
    -- build UI
    local ls = Instance.new("Folder"); ls.Name="leaderstats"; ls.Parent=plr
    local money = Instance.new("IntValue"); money.Name="Money"; money.Parent=ls
    local level = Instance.new("IntValue"); level.Name="Level"; level.Parent=ls
    local xp    = Instance.new("IntValue"); xp.Name="XP";    xp.Parent=ls

    local ess = Instance.new("Folder"); ess.Name="Essence"; ess.Parent=plr
    for _,n in ipairs({"Fire","Water","Earth"}) do Instance.new("IntValue", ess).Name = n end

    -- force-load now, then mirror
    local d = Data.EnsureLoaded(plr)
    money.Value = d.Money or 0
    level.Value = d.Level or 1
    xp.Value    = d.XP    or 0
end)

Players.PlayerRemoving:Connect(function(plr)
    pcall(function() Data.SaveNow(plr) end)
end)
