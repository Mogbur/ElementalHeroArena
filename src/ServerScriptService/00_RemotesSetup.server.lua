-- ReplicatedStorage/RemotesSetup.server.lua
local RS = game:GetService("ReplicatedStorage")

-- Ensure folder
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local function ensureRemote(name)
	-- prefer inside Remotes; keep any root duplicates you already have
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
end

-- your existing ones
ensureRemote("OpenEquipMenu")
ensureRemote("SkillPurchaseRequest")
ensureRemote("SkillEquipRequest")
ensureRemote("WaveText")
ensureRemote("WaveBanner")

-- NEW ones used by skills / vfx / damage text
ensureRemote("CastSkillRequest")  -- client -> server: “cast my equipped skill now”
ensureRemote("SkillVFX")          -- server -> all clients: beams / rings / shields
ensureRemote("DamageNumbers")     -- server -> all clients: floating numbers
