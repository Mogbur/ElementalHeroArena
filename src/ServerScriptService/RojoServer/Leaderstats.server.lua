-- ServerScriptService/RojoServer/Leaderstats.server.lua
local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local Data = require(SSS.RojoServer.Data.PlayerData)

Players.PlayerAdded:Connect(function(plr)
    -- leaderstats root
    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    ls.Parent = plr

    -- Keep Level + XP (names unchanged so your Data mirror still updates them)
    local level = Instance.new("IntValue")
    level.Name = "Level"
    level.Parent = ls

    local xp = Instance.new("IntValue")
    xp.Name = "XP"
    xp.Parent = ls

    -- Replace Money -> E.Flux
    local fluxIv = Instance.new("IntValue")
    fluxIv.Name = "E.Flux"
    fluxIv.Parent = ls

    -- Essence folder on the player (unchanged)
    local ess = Instance.new("Folder")
    ess.Name = "Essence"
    ess.Parent = plr
    for _, n in ipairs({ "Fire", "Water", "Earth" }) do
        local iv = Instance.new("IntValue")
        iv.Name = n
        iv.Parent = ess
    end

    -- Force-load now, then initial sync
    local d = Data.EnsureLoaded(plr)
    level.Value  = (d and d.Level) or 1
    xp.Value     = (d and d.XP)    or 0
    fluxIv.Value = (d and d.Flux)  or 0

    -- Live sync: Level/XP are already mirrored by Data module if the names match.
    -- Flux is not mirrored to leaderstats by that module, but Flux *attribute* is.
    plr:GetAttributeChangedSignal("Flux"):Connect(function()
        fluxIv.Value = plr:GetAttribute("Flux") or fluxIv.Value
    end)
end)

Players.PlayerRemoving:Connect(function(plr)
    pcall(function() Data.SaveNow(plr) end)
end)
