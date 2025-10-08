-- ResourceTray.client.lua
-- Simple, collapsible resource tray that mirrors player attributes.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

-- === CONFIG ===
local ICONS = {
	-- replace with your transparent PNGs (Images folder in ReplicatedStorage or rbxassetid)
	Money = "rbxassetid://123456",    -- coin
	Flux  = "rbxassetid://123457",    -- flux crystal
	Fire  = "rbxassetid://123458",
	Water = "rbxassetid://123459",
	Earth = "rbxassetid://123460",
}

local SHOW = { "Fire", "Water", "Earth" }  -- order for essence list

-- attribute names already mirrored by your PlayerData
-- (Money is leaderstats, Flux we'll mirror as a player attribute below)
local ATTR = {
	Fire  = "Essence_Fire",
	Water = "Essence_Water",
	Earth = "Essence_Earth",
	Flux  = "Flux",         -- add in PlayerData (see server patch)
}

-- === UI ROOTS ===
local gui = Instance.new("ScreenGui")
gui.Name = "ResourceTray"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PG

-- Top-left currencies container (Money + Flux)
local topLeft = Instance.new("Frame")
topLeft.Name = "TopLeftChips"
topLeft.AnchorPoint = Vector2.new(0,0)
topLeft.Position = UDim2.fromOffset(14, 12)
topLeft.Size = UDim2.fromOffset(260, 44)
topLeft.BackgroundTransparency = 1
topLeft.Parent = gui

local row = Instance.new("UIListLayout", topLeft)
row.FillDirection = Enum.FillDirection.Horizontal
row.HorizontalAlignment = Enum.HorizontalAlignment.Left
row.Padding = UDim.new(0, 8)

-- Collapsible left tray
local tray = Instance.new("Frame")
tray.Name = "Tray"
tray.AnchorPoint = Vector2.new(0,0.5)
tray.Position = UDim2.new(0, 10, 0.5, -30)
tray.Size = UDim2.fromOffset(210, 280)
tray.BackgroundTransparency = 0.25
tray.BackgroundColor3 = Color3.fromRGB(10,10,10)
tray.Visible = true
tray.Parent = gui

do
	local stroke = Instance.new("UIStroke", tray)
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0,0,0)
	Instance.new("UICorner", tray).CornerRadius = UDim.new(0,10)
end

-- slide open/close button (tiny tab)
local tab = Instance.new("TextButton")
tab.Name = "Tab"
tab.AnchorPoint = Vector2.new(0,0.5)
tab.Position = UDim2.new(0, tray.AbsoluteSize.X + 6, 0.5, 0)
tab.Size = UDim2.fromOffset(24, 72)
tab.Text = "⟨⟩"
tab.TextScaled = true
tab.BackgroundColor3 = Color3.fromRGB(10,10,10)
tab.BackgroundTransparency = 0.25
tab.Parent = tray

Instance.new("UICorner", tab).CornerRadius = UDim.new(0,8)
Instance.new("UIStroke", tab).Thickness = 2

local open = true
local function setOpen(on)
	open = on
	if on then
		tray:TweenSize(UDim2.fromOffset(210, 280), "Out", "Quad", 0.15, true)
		tab.Text = "⟨⟩"
	else
		tray:TweenSize(UDim2.fromOffset(12, 110), "Out", "Quad", 0.15, true)
		tab.Text = "⟩"
	end
end
tab.Activated:Connect(function() setOpen(not open) end)

-- Scroll list for essences
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.AnchorPoint = Vector2.new(0,0)
list.Position = UDim2.fromOffset(6, 6)
list.Size = UDim2.new(1, -12, 1, -12)
list.BackgroundTransparency = 1
list.CanvasSize = UDim2.new(0,0,0,0)
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.BorderSizePixel = 0
list.Parent = tray

local vlist = Instance.new("UIListLayout", list)
vlist.Padding = UDim.new(0, 6)
vlist.HorizontalAlignment = Enum.HorizontalAlignment.Left

local function mkChip(iconId, labelText)
	local b = Instance.new("ImageButton")
	b.AutoButtonColor = true
	b.BackgroundTransparency = 0.35
	b.BackgroundColor3 = Color3.fromRGB(20,20,20)
	b.Size = UDim2.fromOffset(186, 44)
	b.Image = ""
	Instance.new("UICorner", b).CornerRadius = UDim.new(0,10)
	Instance.new("UIStroke", b).Thickness = 1

	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromOffset(36,36)
	img.Position = UDim2.fromOffset(6,4)
	img.Image = iconId or ""
	img.Parent = b

	local txt = Instance.new("TextLabel")
	txt.Name = "Amount"
	txt.BackgroundTransparency = 1
	txt.Text = labelText or "0"
	txt.Font = Enum.Font.GothamBold
	txt.TextScaled = true
	txt.TextColor3 = Color3.fromRGB(255,255,255)
	txt.Position = UDim2.fromOffset(48, 4)
	txt.Size = UDim2.new(1, -54, 1, -8)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.Parent = b

	return b, txt
end

-- Currency chips (top-left)
local moneyChip, moneyTxt = mkChip(ICONS.Money, "0")
moneyChip.Size = UDim2.fromOffset(120, 36)
moneyChip.Parent = topLeft

local fluxChip, fluxTxt = mkChip(ICONS.Flux, "0")
fluxChip.Size = UDim2.fromOffset(120, 36)
fluxChip.Parent = topLeft

-- Essence chips in the tray
local essenceText = {}
for _, key in ipairs(SHOW) do
	local chip, txt = mkChip(ICONS[key], "0")
	chip.Parent = list
	essenceText[key] = txt
end

-- === BINDINGS ===
local function fmt(n)
	if n >= 1e6 then return string.format("%.1fm", n/1e6)
	elseif n >= 1e3 then return string.format("%.1fk", n/1e3)
	else return tostring(n) end
end

local function bindLeaderstat(statName, setter)
	local ls = LP:WaitForChild("leaderstats", 10)
	if not ls then return end
	local v = ls:FindFirstChild(statName)
	if v and v:IsA("NumberValue") then
		setter(v.Value)
		v:GetPropertyChangedSignal("Value"):Connect(function() setter(v.Value) end)
	end
end

bindLeaderstat("Money", function(n) moneyTxt.Text = fmt(n) end)

-- Flux / Essence use attributes; update immediately + on change
local function bindAttr(attrName, setter)
	setter(LP:GetAttribute(attrName) or 0)
	LP:GetAttributeChangedSignal(attrName):Connect(function()
		setter(LP:GetAttribute(attrName) or 0)
	end)
end

bindAttr(ATTR.Flux, function(n) fluxTxt.Text = fmt(n) end)

for key, attr in pairs(ATTR) do
	if key ~= "Flux" then
		bindAttr(attr, function(n)
			if essenceText[key] then essenceText[key].Text = fmt(n) end
		end)
	end
end

-- Start collapsed on phone
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	setOpen(false)
end
