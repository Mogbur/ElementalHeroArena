-- ServerScriptService/RojoServer/Systems/ForgeRF.server.lua
local RS  = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local ForgeRF = Remotes:WaitForChild("ForgeRF")

local SSS = game:GetService("ServerScriptService")
-- robust require for the module under RojoServer/Modules
local Forge = require(SSS:WaitForChild("RojoServer"):WaitForChild("Modules"):WaitForChild("ForgeService"))

local function plotOf(plr)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, p in ipairs(plots:GetChildren()) do
        if p:IsA("Model") and (p:GetAttribute("OwnerUserId") or 0) == plr.UserId then
            return p
        end
    end
end

ForgeRF.OnServerInvoke = function(plr, cmd, wave, payload)
    local plot = plotOf(plr)
    if not plot then
        if cmd == "offers" then
            -- Still allow UI to open without a plot, but return a clear failure
            return { core = nil, util = nil, reroll = { cost = 40, free = false } }
        end
        return false, "no-plot"
    end

    if cmd == "offers" then
        -- client only sends wave; the offer uses internal per-run cache
        return Forge:Offers(plr, wave)
    elseif cmd == "buy" then
        -- spam guard for purchases only
        local now = os.clock()
        local nextT = plr:GetAttribute("__ForgeNext") or 0
        if now < nextT then return false, "cooldown" end
        plr:SetAttribute("__ForgeNext", now + 0.25)

        payload = payload or {}
        payload.plot = plot -- ignore any client-supplied plot
        return Forge:Buy(plr, wave, payload)
    else
        return false, "bad_cmd"
    end
end
