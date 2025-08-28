-- ServerScriptService/RemotesInit (Script)
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
ensure(Remotes, "RemoteEvent", "OpenEquipMenu")
ensure(Remotes, "RemoteEvent", "SkillPurchaseRequest")
ensure(Remotes, "RemoteEvent", "SkillEquipRequest")

local ServerEvents = ensure(ServerStorage, "Folder", "ServerEvents")
ensure(ServerEvents, "BindableEvent", "FightStarted")

print("[RemotesInit] Remotes ready")
