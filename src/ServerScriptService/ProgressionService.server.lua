-- ServerScriptService/ProgressionService.server.lua
-- Creates the Remotes used by the equip menu + initializes player progression.
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")

-- put remotes in RS/Remotes (create if missing)
local function getRemotesFolder()
    local f = ReplicatedStorage:FindFirstChild("Remotes")
    if not f then
        f = Instance.new("Folder")
        f.Name = "Remotes"
        f.Parent = ReplicatedStorage
    end
    return f
end

local function ensureEvent(name)
    local rem = getRemotesFolder()
    local e = rem:FindFirstChild(name)
    if not e then
        e = Instance.new("RemoteEvent")
        e.Name = name
        e.Parent = rem
    end
    return e
end

-- your module (server-only)
local Progression = require(ServerScriptService.RojoServer.Modules.Progression)


ensureEvent("OpenEquipMenu")
ensureEvent("SkillPurchaseRequest")
ensureEvent("SkillEquipRequest")

-- === Progression init ===
local SSS = game:GetService("ServerScriptService")
local Progression = require(SSS.RojoServer.Modules.Progression)

local function onPlayerAdded(plr)
	Progression.InitPlayer(plr)
end

-- Studio can have players already present:
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)
