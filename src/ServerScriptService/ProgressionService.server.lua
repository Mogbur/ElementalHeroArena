-- ServerScriptService/ProgressionService.server.lua
-- Creates the Remotes used by the equip menu + initializes player progression.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

-- === Ensure Remotes exist (safe to run multiple times) ===
local rem = RS:FindFirstChild("Remotes")
if not rem then
	rem = Instance.new("Folder")
	rem.Name = "Remotes"
	rem.Parent = RS
end

local function ensureEvent(name)
	local e = rem:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = rem
	end
	return e
end

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
