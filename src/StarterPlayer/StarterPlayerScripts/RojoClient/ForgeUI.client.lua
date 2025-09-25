-- RojoClient/ForgeUI.client.lua
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")

local RE_Open  = Remotes:WaitForChild("OpenForgeUI")
local RE_Close = Remotes:FindFirstChild("CloseForgeUI") -- optional
local RF_Forge = Remotes:WaitForChild("ForgeRF")

local GuiService = game:GetService("GuiService")        -- NEW
local UIS        = game:GetService("UserInputService")  -- NEW
local CAS        = game:GetService("ContextActionService") -- NEW (if you want to add a keybind to close the UI)

-- prevent double-purchase (mouse+touch/gamepad firing together)
local buying = false

local lp  = Players.LocalPlayer

-- unified binder (mouse + touch + gamepad)
local function bind(btn, fn)
	btn.Activated:Connect(fn)
end

-- =============== UI ===============
local gui = Instance.new("ScreenGui")
gui.Name = "ForgeUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn   = false
gui.Enabled        = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling        -- NEW
gui.Parent = lp:WaitForChild("PlayerGui")

-- kill the white selection outline (gamepad highlight)
local noSel = Instance.new("ImageLabel")
noSel.Name = "NoSel"
noSel.BackgroundTransparency = 1
noSel.ImageTransparency = 1
noSel.Size = UDim2.fromOffset(1,1)
noSel.Parent = gui

local root = Instance.new("Frame")
root.AnchorPoint        = Vector2.new(0.5, 0.5)
root.Position           = UDim2.fromScale(0.5, 0.5)
root.Size               = UDim2.fromScale(0.38, 0.32)
root.BackgroundColor3   = Color3.fromRGB(24, 28, 44)
root.BackgroundTransparency = 0.05
root.SelectionGroup = true                               -- NEW (gamepad focus group)
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", root); stroke.Thickness = 2; stroke.Transparency = 0.25

-- keep aspect nice on phones                              -- NEW
local ar = Instance.new("UIAspectRatioConstraint")
ar.AspectRatio = 2.2
ar.Parent = root
if UIS.TouchEnabled then
	root.Size = UDim2.fromScale(0.9, 0.36)
end

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(235,240,255)
title.Text = "Elemental Forge"
title.Size = UDim2.new(1, -20, 0, 40)
title.Position = UDim2.new(0, 10, 0, 8)
title.Parent = root

local close = Instance.new("TextButton")
close.Text = "×" -- looks cleaner than "X"
close.Font = Enum.Font.GothamBold
close.TextScaled = true
close.TextColor3 = Color3.fromRGB(220,225,240)
close.Size = UDim2.fromOffset(36, 36)
close.Position = UDim2.new(1, -42, 0, 8)
close.BackgroundColor3 = Color3.fromRGB(42, 46, 64)
close.ZIndex = 5
close.Selectable = true                                  -- NEW
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
close.Parent = root

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, -20, 1, -78)
body.Position = UDim2.new(0, 10, 0, 50)
body.Parent = root

local list = Instance.new("UIListLayout", body)
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment   = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0, 10)

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextColor3 = Color3.fromRGB(150, 160, 200)
hint.TextScaled = true
hint.Text = "Core upgrades reset on death."
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -6)
hint.Size = UDim2.new(1, -24, 0, 18)
local hintSize = Instance.new("UITextSizeConstraint", hint)
hintSize.MinTextSize = 12
hintSize.MaxTextSize = 16
hint.Parent = root

-- return real references so we never index strings
local function makeCard(titleText)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0.5, -8, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(30, 35, 56)
	card.BackgroundTransparency = 0.05
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(230,235,255)
	t.Text = titleText
	t.Size = UDim2.new(1, -16, 0, 34)
	t.Position = UDim2.new(0, 8, 0, 6)
	t.Parent = card

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "NameLbl"
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.Gotham
	nameLbl.TextScaled = true
	nameLbl.TextColor3 = Color3.fromRGB(200,210,255)
	nameLbl.Text = ""
	nameLbl.Size = UDim2.new(1, -16, 0, 32)
	nameLbl.Position = UDim2.new(0, 8, 0, 44)
	nameLbl.Parent = card

	local subLbl = Instance.new("TextLabel")
	subLbl.Name = "SubLbl"
	subLbl.BackgroundTransparency = 1
	subLbl.Font = Enum.Font.Gotham
	subLbl.TextScaled = true
	subLbl.LineHeight = 1.08
	subLbl.TextColor3 = Color3.fromRGB(170,180,220)
	subLbl.Text = ""
	subLbl.Size = UDim2.new(1, -16, 0, 62)          -- was 28
	subLbl.Position = UDim2.new(0, 8, 0, 80)
	local subSize = Instance.new("UITextSizeConstraint", subLbl)
	subSize.MinTextSize = 16
	subSize.MaxTextSize = 24                          -- a touch smaller than “+8% Attack”
	subLbl.Parent = card

	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.AutoButtonColor = true
	buyBtn.Text = ""
	buyBtn.Font = Enum.Font.GothamBlack
	buyBtn.TextScaled = true
	buyBtn.TextColor3 = Color3.fromRGB(255,255,255)
	buyBtn.Size = UDim2.new(1, -16, 0, 44)
	buyBtn.Position = UDim2.new(0, 8, 1, -52)
	buyBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 210)
	buyBtn.Selectable = true                               -- NEW
	Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 10)
	buyBtn.Parent = card

	card.Parent = body
	return {frame = card, name = nameLbl, sub = subLbl, buy = buyBtn}
end

local cardCore = makeCard("Core Upgrade")
local cardUtil = makeCard("Utility")

-- remove focus outline on buttons/close
cardCore.buy.SelectionImageObject = noSel
cardUtil.buy.SelectionImageObject = noSel
close.SelectionImageObject        = noSel

-- Declare the plot ref early (doBuy uses it)
local plotCurrent: Model? = nil

-- =============== helpers ===============
local function currentWaveOfPlot(p)
	local ok, w = pcall(function() return p:GetAttribute("CurrentWave") end)
	return (ok and tonumber(w)) or 1
end

local function showErrorMessage(card, key)
	local map = {
		poor       = "Not enough money",
		no_shrine  = "Forge not available",
		not_owner  = "Not your plot",
		no_money   = "No Money stat",
		bad_choice = "Bad choice",
		error      = "Server error",
		max        = "Already at MAX",   -- << add this line
	}
	local msg = map[key] or tostring(key or "failed")
	task.defer(function()
		card.sub.Text = msg
	end)
end

local function refreshOffers()
	if not plotCurrent or not plotCurrent.Parent then gui.Enabled = false; return end
	local wave = currentWaveOfPlot(plotCurrent)
	local ok, offers = pcall(function() return RF_Forge:InvokeServer("offers", wave) end)
	if not ok or type(offers) ~= "table" then
		cardCore.sub.Text, cardUtil.sub.Text = "Failed to fetch", "Failed to fetch"
		return
	end

	-- core (now shows current → next % and supports tier 0..3)
	local core  = offers.core or {}
	local tier  = core.tier  or 0         -- 0..3
	local pct   = core.pct   or 8
	local price = core.price or 0

	local nowPct  = pct * tier
	local nextPct = pct * math.clamp(tier + 1, 0, 3)

	cardCore.name.Text = core.name or core.id or "Core"

	if tier >= 3 then
		cardCore.sub.Text  = ("Tier %d • +%d%% TOTAL"):format(tier, nowPct)
		cardCore.buy.Text  = "MAX"
		cardCore.buy.AutoButtonColor = false
		cardCore.buy.Active = false
		cardCore.buy.BackgroundColor3 = Color3.fromRGB(60,110,210)
	else
		cardCore.sub.Text = ("Tier %d → %d\n%d%% → +%d%%\n%d$")
			:format(tier, tier+1, nowPct, nextPct, price)
		cardCore.buy.Text  = ("Upgrade (%d)"):format(price)
		cardCore.buy.AutoButtonColor = true
		cardCore.buy.Active = true
		cardCore.buy.BackgroundColor3 = Color3.fromRGB(60,110,210)
	end

	-- util (restored)
	local util   = offers.util or {}
	local uPrice = util.price or 0
	cardUtil.name.Text = util.name or util.id or "Utility"
	cardUtil.sub.Text  = ("%d$"):format(uPrice)
	cardUtil.buy.Text  = ("Buy (%d)"):format(uPrice)
	cardUtil.buy.AutoButtonColor = true
	cardUtil.buy.Active = true
	cardUtil.buy.BackgroundColor3 = Color3.fromRGB(90,145,95)
end

-- buys (define this BEFORE we bind buttons)
local function doBuy(kind)
	if buying then return end
	if not plotCurrent or not plotCurrent.Parent then return end

	buying = true
	cardCore.buy.Active = false
	cardUtil.buy.Active = false

	local wave = currentWaveOfPlot(plotCurrent)
	local payload = { type = kind, plot = plotCurrent }
	local ok, res, why = pcall(function() return RF_Forge:InvokeServer("buy", wave, payload) end)

	if not ok then
		showErrorMessage(kind=="CORE" and cardCore or cardUtil, "error")
	else
		if res ~= true then
			showErrorMessage(kind=="CORE" and cardCore or cardUtil, why)
		else
			if kind == "CORE" then
				cardCore.sub.Text = "Upgraded!"
				cardCore.buy.AutoButtonColor = false
				cardCore.buy.BackgroundColor3 = Color3.fromRGB(42,46,64)
				task.delay(0.25, refreshOffers)
			else
				if type(why) == "table" and why.util == "REROLL" then
					cardUtil.sub.Text = "Rerolled"
					task.delay(0.15, refreshOffers)
				elseif type(why) == "table" and why.util == "RECOVER" then
					cardUtil.sub.Text = "Recovered"
				end
			end
		end
	end

	cardCore.buy.Active = true
	cardUtil.buy.Active = true
	buying = false
end

-- === BIND BUTTONS (AFTER doBuy) ===
bind(close, function()
    gui.Enabled = false
    CAS:UnbindAction("ForgeClose")
end)
bind(cardCore.buy, function() doBuy("CORE") end)
bind(cardUtil.buy, function() doBuy("UTIL") end)

-- gamepad left/right between buttons
cardCore.buy.NextSelectionRight = cardUtil.buy
cardUtil.buy.NextSelectionLeft  = cardCore.buy

-- =============== open/close ===============
RE_Open.OnClientEvent:Connect(function(plot)
	plotCurrent = plot
	gui.Enabled = true
	GuiService.SelectedObject = cardCore.buy

	CAS:BindAction(
		"ForgeClose",
		function(_, state)
			if state ~= Enum.UserInputState.Begin then return end
			gui.Enabled = false
			CAS:UnbindAction("ForgeClose")
			return Enum.ContextActionResult.Sink
		end,
		true,
		Enum.KeyCode.Escape,      -- keyboard
		Enum.KeyCode.ButtonB      -- gamepad
	)
	refreshOffers()
end)

if RE_Close then
	RE_Close.OnClientEvent:Connect(function(_plot)
		if _plot == nil or _plot == plotCurrent then
			gui.Enabled = false
			CAS:UnbindAction("ForgeClose")
		end
	end)
end
