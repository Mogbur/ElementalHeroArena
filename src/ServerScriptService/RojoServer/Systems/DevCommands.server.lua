-- ServerScriptService/RojoServer/Systems/DevCommands.server.lua
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RS   = game:GetService("ReplicatedStorage")
local SSS  = game:GetService("ServerScriptService")

local WeaponStyles = require(RS.Modules.WeaponStyles)
local SkillConfig  = require(RS.Modules.SkillConfig)
local Data         = require(SSS.RojoServer.Data.PlayerData)

local Remotes = RS:WaitForChild("Remotes")
local OpenEquipMenu = Remotes:FindFirstChild("OpenEquipMenu")

local function findPlotFor(plr)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _,p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and (p:GetAttribute("OwnerUserId") or 0) == plr.UserId then
			return p
		end
	end
end

local function refreshBars(plr)
	local ch = plr.Character
	if ch then
		ch:SetAttribute("BarsVisible", 0)
		ch:SetAttribute("BarsVisible", 1)
	end
end

local function resetPlayer(plr: Player, mode: string?)
	mode = tostring(mode or ""):lower()

	-- Level / XP
	plr:SetAttribute("Level", 1)
	plr:SetAttribute("XP", 0)

	-- Styles → L1, 0xp
	for styleId,_ in pairs(WeaponStyles) do
		plr:SetAttribute("StyleLevel_"..styleId, 1)
		plr:SetAttribute("StyleXP_"..styleId, 0)
	end

	-- Skills → Lv1 for *all* (fast testing)
	for id,_ in pairs(SkillConfig or {}) do
		plr:SetAttribute("Skill_"..id, 1)
	end
	-- minimal option (only Firebolt)
	if mode == "minimal" then
		for id,_ in pairs(SkillConfig or {}) do
			if id ~= "firebolt" then plr:SetAttribute("Skill_"..id, 0) end
		end
	end

	-- Equip defaults
	plr:SetAttribute("Equip_Primary", "firebolt")
	plr:SetAttribute("Equip_Secondary", "")
	plr:SetAttribute("Equip_Utility", "")
	plr:SetAttribute("WeaponMain", "Sword")
	plr:SetAttribute("WeaponOff",  "Shield")

	-- Plot bits (waves/buffs/cores/blessings/utilities)
	local plot = findPlotFor(plr)
	if plot then
		plot:SetAttribute("CurrentWave", 1)
		plot:SetAttribute("BlessingElem", nil)
		plot:SetAttribute("BlessingExpiresSegId", -1)
		plot:SetAttribute("Util_OverchargePct", 0)
		plot:SetAttribute("Util_SecondWindLeft", 0)
		-- leave core as-is
		-- plot:SetAttribute("CoreId", nil); plot:SetAttribute("CoreTier", 0)
	end

	-- Clear shield & refresh bars
	local ch = plr.Character
	if ch then
		ch:SetAttribute("ShieldHP", 0)
		ch:SetAttribute("ShieldMax", 0)
		ch:SetAttribute("ShieldExpireAt", 0)
	end

	refreshBars(plr)
	if OpenEquipMenu then OpenEquipMenu:FireClient(plr) end
	print("[DevCommands] Reset done for", plr.Name)
end

-- === New helpers ===

-- !setlevel <n>  → sets Level by adjusting XP using your simple curve (100 XP per level)
local function setLevel(plr: Player, lvlAny)
	local lvl = math.max(1, math.floor(tonumber(lvlAny) or 1))
	local d = Data.Get(plr) or Data.EnsureLoaded(plr)
	local curXP = (d and d.XP) or 0
	local targetXP = (lvl - 1) * 100
	local delta = targetXP - curXP
	if delta ~= 0 then
		Data.AddXP(plr, delta) -- mirrors Level/XP + attributes
	end
	refreshBars(plr)
	print(string.format("[DevCommands] %s -> Level %d", plr.Name, lvl))
end

-- !giveflux <n> → adds (or subtracts with negative) Flux; clamped >= 0 by your Data module
local function giveFlux(plr: Player, amtAny)
	local amt = math.floor(tonumber(amtAny) or 0)
	if amt == 0 then return end
	Data.AddFlux(plr, amt)
	print(string.format("[DevCommands] %s Flux %+d (now %s)", plr.Name, amt, tostring(plr:GetAttribute("Flux"))))
end

local function handle(plr, raw)
	local msg = string.lower(raw or "")

	-- reset
	if msg == "!resetme" or msg == "/resetme" or msg == "resetme" then
		resetPlayer(plr)
		return
	elseif msg == "!resetme minimal" then
		resetPlayer(plr, "minimal"); return
	end

	-- setlevel
	do
		local n = raw:match("^%s*[%!/]*setlevel%s+(%-?%d+)%s*$")
		if n then setLevel(plr, n); return end
	end

	-- giveflux
	do
		local n = raw:match("^%s*[%!/]*giveflux%s+(%-?%d+)%s*$")
		if n then giveFlux(plr, n); return end
	end
end

-- Legacy chat
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(m) handle(plr, m) end)
end)

-- New TextChatService
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local src = message.TextSource
		if src then
			local plr = Players:GetPlayerByUserId(src.UserId)
			if plr then handle(plr, message.Text) end
		end
		return nil -- keep normal chat behavior
	end
end

print("[DevCommands] Dev commands ready: !resetme | !resetme minimal | !setlevel <n> | !giveflux <n>")
