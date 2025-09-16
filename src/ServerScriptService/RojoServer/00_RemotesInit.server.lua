local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")

-- Folder
local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder", RS)
Remotes.Name = "Remotes"

local function ensure(name, class)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new(class or "RemoteEvent"); r.Name = name; r.Parent = Remotes end
	return r
end

-- Core/game remotes
ensure("OpenEquipMenu")
ensure("SkillPurchaseRequest")
ensure("SkillEquipRequest")
ensure("WaveText")
ensure("CheckpointRF",   "RemoteFunction")
ensure("OpenCheckpointUI","RemoteEvent")
-- (WaveBanner is gone, do not recreate)

-- Skills/VFX
ensure("CastSkillRequest")
ensure("SkillVFX")
ensure("DamageNumbers")

-- Forge
local ForgeRF     = ensure("ForgeRF", "RemoteFunction")
local OpenForgeUI = ensure("OpenForgeUI", "RemoteEvent")
local ForgeHUD    = ensure("ForgeHUD", "RemoteEvent")
local CloseForge  = ensure("CloseForgeUI", "RemoteEvent")

-- Optional server-only events
local ServerEvents = SS:FindFirstChild("ServerEvents") or Instance.new("Folder", SS)
ServerEvents.Name = "ServerEvents"
if not ServerEvents:FindFirstChild("FightStarted") then
	Instance.new("BindableEvent", ServerEvents).Name = "FightStarted"
end

-- Robust require for ForgeService (RojoServer/Modules OR Modules)
local function requireForge()
	local rojo = SSS:FindFirstChild("RojoServer")
	if rojo and rojo:FindFirstChild("Modules") and rojo.Modules:FindFirstChild("ForgeService") then
		return require(rojo.Modules.ForgeService)
	end
	return require(SSS:WaitForChild("Modules"):WaitForChild("ForgeService"))
end
local Forge = requireForge()

print("[RemotesInit] Remotes ready")
