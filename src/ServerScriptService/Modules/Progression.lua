local Progression = {}
local SSS = game:GetService("ServerScriptService")
local Progression = require(SSS.RojoServer.Modules.Progression)

local MAX_LEVEL = 50
local function xpToNext(level) return math.floor(20 + (level ^ 1.75) * 8) end
local function findPlayersPlot(uid)
	local container = workspace:FindFirstChild("Plots") or workspace
	for _, m in ipairs(container:GetChildren()) do
		if m:IsA("Model") and m.Name:match("^BasePlot%d+$") then
			if (m:GetAttribute("OwnerUserId") or 0) == uid then return m end
		end
	end
end
function Progression.InitPlayer(plr)
	if plr:GetAttribute("HeroLevel")==nil then plr:SetAttribute("HeroLevel",1) end
	if plr:GetAttribute("HeroXP")==nil then plr:SetAttribute("HeroXP",0) end
end
function Progression.AddXP(plr, amount)
	if amount<=0 then return end
	Progression.InitPlayer(plr)
	local lvl=plr:GetAttribute("HeroLevel") or 1
	local xp=plr:GetAttribute("HeroXP") or 0
	xp+=math.floor(amount)
	local gained=0
	while lvl<MAX_LEVEL do
		local need=xpToNext(lvl); if xp<need then break end
		xp-=need; lvl+=1; gained+=1
	end
	plr:SetAttribute("HeroLevel", lvl); plr:SetAttribute("HeroXP", xp)
	local plot=findPlayersPlot(plr.UserId); if plot then plot:SetAttribute("HeroLevel", lvl) end
end
return Progression
