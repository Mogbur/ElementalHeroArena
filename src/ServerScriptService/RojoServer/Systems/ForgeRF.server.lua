-- ServerScriptService/RojoServer/Systems/ForgeRF.server.lua
local RS   = game:GetService("ReplicatedStorage")
local SSS  = game:GetService("ServerScriptService")

-- Find ForgeService module (your layout supports either spot)
local Forge = (function()
	local ok, mod = pcall(function() return require(SSS.RojoServer.Modules.ForgeService) end)
	if ok and mod then return mod end
	return require(SSS:WaitForChild("Modules"):WaitForChild("ForgeService"))
end)()

-- Remotes folder + helpers
local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder", RS)
Remotes.Name = "Remotes"
local function ensureRE(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent", Remotes); r.Name = name end
	return r
end
local function ensureRF(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteFunction", Remotes); r.Name = name end
	return r
end

-- Ensure the three channels used by Forge exist
ensureRE("OpenForgeUI")
ensureRE("ForgeHUD")
ensureRE("CloseForgeUI")  -- optional: auto-close client UI
local RF = ensureRF("ForgeRF")

-- RF handler
RF.OnServerInvoke = function(plr, action, ...)
	if action == "offers" then
		-- wave is advisory; the service will read plot’s state
		return Forge:Offers(plr, ...)
	elseif action == "buy" then
		local ok, res, why = pcall(function() return Forge:Buy(plr, ...) end)
		if not ok then
			warn("[ForgeRF] Buy error:", res)
			return false, "error"
		end
		return res, why
	end
	return nil
end
