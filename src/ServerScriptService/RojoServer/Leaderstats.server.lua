local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local Data = require(SSS:WaitForChild("RojoServer"):WaitForChild("Data"):WaitForChild("PlayerData"))

Players.PlayerAdded:Connect(function(plr)
    local ls = Instance.new("Folder"); ls.Name="leaderstats"; ls.Parent=plr
    local money = Instance.new("IntValue"); money.Name="Money"; money.Parent=ls
    local level = Instance.new("IntValue"); level.Name="Level"; level.Parent=ls
    local xp    = Instance.new("IntValue"); xp.Name="XP";    xp.Parent=ls

    local ess = Instance.new("Folder"); ess.Name="Essence"; ess.Parent=plr
    for _,n in ipairs({"Fire","Water","Earth"}) do
        local v=Instance.new("IntValue"); v.Name=n; v.Parent=ess
    end

    -- mirror from persisted data (safe defaults)
    local d = Data.Get(plr) or {}
    money.Value = d.Money or 0
    level.Value = d.Level or 1
    xp.Value    = d.XP    or 0
    -- if you persist essences later, mirror them here too
end)

Players.PlayerRemoving:Connect(function(plr)
    pcall(function() Data.SaveNow(plr) end)
end)
