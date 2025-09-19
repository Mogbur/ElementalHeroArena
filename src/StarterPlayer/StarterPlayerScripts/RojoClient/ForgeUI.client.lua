-- RojoClient/ForgeUI.client.lua
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")

local RE_Open   = Remotes:WaitForChild("OpenForgeUI")
local RE_Close  = Remotes:FindFirstChild("CloseForgeUI") -- optional
local RF_Forge  = Remotes:WaitForChild("ForgeRF")

local lp = Players.LocalPlayer

-- =============== UI ===============
local gui = Instance.new("ScreenGui")
gui.Name = "ForgeUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = lp:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position    = UDim2.fromScale(0.5, 0.5)
root.Size        = UDim2.fromScale(0.38, 0.32)
root.BackgroundColor3 = Color3.fromRGB(24, 28, 44)
root.BackgroundTransparency = 0.05
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", root); stroke.Thickness = 2; stroke.Transparency = 0.25

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
close.Text = "✕"
close.Font = Enum.Font.GothamBold
close.TextScaled = true
close.TextColor3 = Color3.fromRGB(220,225,240)
close.Size = UDim2.fromOffset(36, 36)
close.Position = UDim2.new(1, -42, 0, 8)
close.BackgroundColor3 = Color3.fromRGB(42, 46, 64)
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
close.Parent = root
close.MouseButton1Click:Connect(function() gui.Enabled = false end)

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, -20, 1, -60)
body.Position = UDim2.new(0, 10, 0, 50)
body.Parent = root

local list = Instance.new("UIListLayout", body)
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0, 10)

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

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.Gotham
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(200,210,255)
	name.Text = ""
	name.Size = UDim2.new(1, -16, 0, 32)
	name.Position = UDim2.new(0, 8, 0, 44)
	name.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(170,180,220)
	sub.Text = ""
	sub.Size = UDim2.new(1, -16, 0, 28)
	sub.Position = UDim2.new(0, 8, 0, 80)
	sub.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "Buy"
	btn.AutoButtonColor = true
	btn.Text = ""
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(255,255,255)
	btn.Size = UDim2.new(1, -16, 0, 44)
	btn.Position = UDim2.new(0, 8, 1, -52)
	btn.BackgroundColor3 = Color3.fromRGB(60, 110, 210)
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	btn.Parent = card

	card.Parent = body
	return card
end

local cardCore = makeCard("Core Upgrade")
local cardUtil = makeCard("Utility")

local plotCurrent: Model? = nil

-- =============== helpers ===============
local function currentWaveOfPlot(p)
	local ok, w = pcall(function() return p:GetAttribute("CurrentWave") end)
	return (ok and tonumber(w)) or 1
end

local function showErrorMessage(card, key)
	local map = {
		poor="Not enough money",
		no_shrine="Forge not available",
		not_owner="Not your plot",
		no_money="No Money stat",
		bad_choice="Bad choice",
		error="Server error",
	}
	local msg = map[key] or tostring(key or "failed")
	task.delay(0, function()
		local lbl = card:FindFirstChild("Sub")
		if lbl and lbl:IsA("TextLabel") then
			lbl.Text = msg
		end
	end)
end

local function refreshOffers()
	if not plotCurrent or not plotCurrent.Parent then
		gui.Enabled = false
		return
	end
	local wave = currentWaveOfPlot(plotCurrent)
	local ok, offers = pcall(function()
		return RF_Forge:InvokeServer("offers", wave)
	end)
	if not ok or type(offers) ~= "table" then
		cardCore.Sub.Text = "Failed to fetch"
		cardUtil.Sub.Text = "Failed to fetch"
		return
	end

	-- core
	local core = offers.core or {}
	cardCore.Name.Text = core.name or core.id or "Core"
	cardCore.Sub.Text  = ("Tier %d • %d$"):format(core.tier or 1, core.price or 0)
	cardCore.Buy.Text  = ("Upgrade (%d)"):format(core.price or 0)
	cardCore.Buy.AutoButtonColor = true
	cardCore.Buy.BackgroundColor3 = Color3.fromRGB(60, 110, 210)
	cardCore.Buy.Active = true

	-- util
	local util = offers.util or {}
	cardUtil.Name.Text = util.name or util.id or "Utility"
	cardUtil.Sub.Text  = ("%d$"):format(util.price or 0)
	cardUtil.Buy.Text  = ("Buy (%d)"):format(util.price or 0)
	cardUtil.Buy.AutoButtonColor = true
	cardUtil.Buy.BackgroundColor3 = Color3.fromRGB(90, 145, 95)
	cardUtil.Buy.Active = true
end

-- buys
local function doBuy(kind)
	if not plotCurrent or not plotCurrent.Parent then return end
	local wave = currentWaveOfPlot(plotCurrent)
	local payload = { type = kind, plot = plotCurrent }
	local ok, res, why = pcall(function()
		return RF_Forge:InvokeServer("buy", wave, payload)
	end)
	if not ok then
		local card = (kind == "CORE") and cardCore or cardUtil
		showErrorMessage(card, "error")
		return
	end
	if res ~= true then
		local card = (kind == "CORE") and cardCore or cardUtil
		showErrorMessage(card, why)
		return
	end

	-- success
	if kind == "CORE" then
		-- gray briefly then refresh offers (tier/price changes)
		cardCore.Sub.Text = "Upgraded!"
		cardCore.Buy.AutoButtonColor = false
		cardCore.Buy.BackgroundColor3 = Color3.fromRGB(42, 46, 64)
		task.delay(0.25, refreshOffers)
	else -- UTIL
		if type(why) == "table" and why.util == "REROLL" then
			cardUtil.Sub.Text = "Rerolled"
			task.delay(0.15, refreshOffers)
		elseif type(why) == "table" and why.util == "RECOVER" then
			cardUtil.Sub.Text = "Recovered"
		end
	end
end

cardCore.Buy.MouseButton1Click:Connect(function() doBuy("CORE") end)
cardUtil.Buy.MouseButton1Click:Connect(function() doBuy("UTIL") end)

-- =============== open/close ===============
RE_Open.OnClientEvent:Connect(function(plot)
	plotCurrent = plot
	gui.Enabled = true
	refreshOffers()
end)

if RE_Close then
	RE_Close.OnClientEvent:Connect(function(_plot)
		if _plot == nil or _plot == plotCurrent then
			gui.Enabled = false
		end
	end)
end
