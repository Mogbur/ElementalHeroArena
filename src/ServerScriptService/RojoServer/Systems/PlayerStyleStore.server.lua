-- PlayerStyleStore.server.lua
-- Loads/saves a player's last equipped weapon style.
-- Writes two player attributes: WeaponMain, WeaponOff
-- Safe in Studio (API access off -> just warns).

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")

local STORE  = nil
local OK, DS = pcall(function() return DataStoreService:GetDataStore("EHA_Style_v1") end)
if OK then STORE = DS else warn("[StyleStore] DataStore unavailable:", DS) end

-- normalize a (main, off) pair to our three legal styles
local function normalize(main: string?, off: string?)
	main = string.lower(tostring(main or "sword"))
	off  = string.lower(tostring(off  or "shield"))
	if main == "bow" then return "Bow", "" end
	if main == "mace" then return "Mace", "" end
	-- default to Sword&Shield
	return "Sword", "Shield"
end

local function setPlayerAttrs(p: Player, main: string, off: string)
	p:SetAttribute("WeaponMain", main)
	p:SetAttribute("WeaponOff",  off)
end

-- simple save queue so we don't spam DS
local pending: {[number]: boolean} = {}
local function enqueueSave(p: Player)
	if pending[p.UserId] then return end
	pending[p.UserId] = true
	task.delay(2, function()
		pending[p.UserId] = nil
		if not STORE then return end
		local main = p:GetAttribute("WeaponMain") or "Sword"
		local off  = p:GetAttribute("WeaponOff") or "Shield"
		local payload = {main = main, off = off}
		local ok, err = pcall(function()
			STORE:SetAsync(("U:%d"):format(p.UserId), payload)
		end)
		if not ok then warn("[StyleStore] Save failed:", err) end
	end)
end

local function loadFor(p: Player)
	local main, off = "Sword", "Shield"
	if STORE then
		local ok, data = pcall(function()
			return STORE:GetAsync(("U:%d"):format(p.UserId))
		end)
		if ok and typeof(data) == "table" then
			main = data.main or main
			off  = data.off  or off
		elseif not ok then
			warn("[StyleStore] Load failed:", data)
		end
	end
	main, off = normalize(main, off)
	setPlayerAttrs(p, main, off)
end

-- When these change, we schedule a save.
local function hookSaves(p: Player)
	for _, attr in ipairs({"WeaponMain","WeaponOff"}) do
		p:GetAttributeChangedSignal(attr):Connect(function()
			enqueueSave(p)
		end)
	end
end

Players.PlayerAdded:Connect(function(p)
	loadFor(p)
	hookSaves(p)
end)

Players.PlayerRemoving:Connect(function(p)
	if not STORE then return end
	local main = p:GetAttribute("WeaponMain") or "Sword"
	local off  = p:GetAttribute("WeaponOff") or "Shield"
	local ok, err = pcall(function()
		STORE:SetAsync(("U:%d"):format(p.UserId), {main = main, off = off})
	end)
	if not ok then warn("[StyleStore] Final save failed:", err) end
end)

-- (Optional) expose a Bindable for other systems if you want instant saves:
-- ServerStorage:WaitForChild("SaveStyleNow", 1) ... etc. (not needed yet)
