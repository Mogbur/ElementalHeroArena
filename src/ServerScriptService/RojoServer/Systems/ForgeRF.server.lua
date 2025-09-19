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
		return Forge:Offers(plr, ...)
	elseif action == "buy" then
		-- NOTE: pass varargs to pcall by calling the function directly
		local ok, res, why = pcall(Forge.Buy, Forge, plr, ...)
		if not ok then
			warn("[ForgeRF] Buy error:", res)
			return false, "error"
		end
		return res, why
	end
	return nil
end
