-- ServerScriptService/RemotesInit.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function ensure(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end

local Remotes = ensure(ReplicatedStorage, "Folder", "Remotes")
-- existing
ensure(Remotes, "RemoteEvent", "OpenEquipMenu")
ensure(Remotes, "RemoteEvent", "SkillPurchaseRequest")
ensure(Remotes, "RemoteEvent", "SkillEquipRequest")

-- NEW (Forge)
local ForgeRF      = ensure(Remotes, "RemoteFunction", "ForgeRF")      -- server offers/buys
local OpenForgeUI  = ensure(Remotes, "RemoteEvent",   "OpenForgeUI")   -- server -> client: open UI
local ForgeHUD     = ensure(Remotes, "RemoteEvent",   "ForgeHUD")      -- server -> client: update chip / clear

-- optional (if your client ever expects this name elsewhere)
-- ensure(Remotes, "RemoteEvent", "WaveBanner")

local ServerEvents = ensure(ServerStorage, "Folder", "ServerEvents")
ensure(ServerEvents, "BindableEvent", "FightStarted")

-- wire ForgeRF
local Forge = require(script.Parent.Modules:WaitForChild("ForgeService"))
Remotes.ForgeRF.OnServerInvoke = function(plr, verb, wave, payload)
    if verb == "offers" then
        return Forge:Offers(plr, wave)
    elseif verb == "buy" then
        -- forward the plot instance so we can mirror attributes for HUD
        if payload and typeof(payload)=="table" then
            payload.plot = payload.plot or (payload.plotRef and payload.plotRef.Target)
        end
        return Forge:Buy(plr, wave, payload or {})
    end
end

print("[RemotesInit] Remotes ready")
