-- ResourceTray.client.lua
-- Simple, collapsible resource tray that mirrors player attributes.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

-- === CONFIG ===
local ICONS = {
	-- replace with your transparent PNGs (Images folder in ReplicatedStorage or rbxassetid)
	Money = "rbxassetid://8581764829",    -- coin
	Flux  = "rbxassetid://13219079846",    -- flux crystal
	Fire  = "rbxassetid://86006404657315",
	Water = "rbxassetid://83220825471966",
	Earth = "rbxassetid://100036266210611",
}

local ELEM_COLOR = {
    Fire  = Color3.fromRGB(255,100,70),
    Water = Color3.fromRGB( 80,160,255),
    Earth = Color3.fromRGB( 90,200,120),
    Flux  = Color3.fromRGB(170, 90,255),
}

-- Show/hide currencies without touching the rest of the HUD
local SHOW_CURRENCY = {
    Money = false,   -- << hide money for now
    Flux  = true,    -- keep flux visible
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
-- invisible selection image so focused chips don’t show a white box
local invisibleSel = Instance.new("ImageLabel")
invisibleSel.Name = "InvisibleSel"
invisibleSel.ImageTransparency = 1
invisibleSel.BackgroundTransparency = 1
invisibleSel.Size = UDim2.fromOffset(1,1)
invisibleSel.Parent = gui

-- Responsive root scale for very small or very large screens
local rootScale = Instance.new("UIScale")
rootScale.Scale = 1
rootScale.Parent = gui

local function autoscale()
    local cam = workspace.CurrentCamera
    local vps = cam and cam.ViewportSize or Vector2.new(1280, 720)
    -- scale by the smaller axis vs a 1280x720 baseline, clamped
    local s = math.clamp(math.min(vps.X/1280, vps.Y/720), 0.85, 1.15)
    rootScale.Scale = s
end

autoscale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.defer(autoscale)
end)
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(autoscale)
end

-- Top-left currencies container (Money + Flux)
local topLeft = Instance.new("Frame")
topLeft.Name = "TopLeftChips"
topLeft.AnchorPoint = Vector2.new(0,0)
topLeft.Position = UDim2.new(0, 10, 0.5, -190)  -- left side, just above the tray
topLeft.Size = UDim2.fromOffset(0, 56)           -- height baseline
topLeft.AutomaticSize = Enum.AutomaticSize.XY     -- width grows to fit chips
topLeft.BackgroundTransparency = 1
topLeft.Parent = gui

local row = Instance.new("UIListLayout", topLeft)
row.FillDirection = Enum.FillDirection.Horizontal
row.HorizontalAlignment = Enum.HorizontalAlignment.Left
row.Padding = UDim.new(0, 12)

-- Collapsible left tray
local tray = Instance.new("Frame")
tray.Name = "Tray"
tray.AnchorPoint = Vector2.new(0,0.5)
tray.Position = UDim2.new(0, 10, 0.5, -30)
tray.Size = UDim2.fromOffset(210, 280)
tray.BackgroundTransparency = 0.55
tray.BackgroundColor3 = Color3.fromRGB(18,18,24)
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
tab.Position = UDim2.new(1, 6, 0.5, 0)
tab.Size = UDim2.fromOffset(24, 72)
tab.Text = "⟨⟩"
tab.TextScaled = true
tab.BackgroundColor3 = Color3.fromRGB(10,10,10)
tab.BackgroundTransparency = 0.25
tab.Parent = tray

Instance.new("UICorner", tab).CornerRadius = UDim.new(0,8)
Instance.new("UIStroke", tab).Thickness = 2
-- Console + touch friendliness
tab.Selectable = true                          -- controller can focus it
if UserInputService.TouchEnabled then          -- bigger hitbox on phones/tablets
    tab.Size = UDim2.fromOffset(32, 96)
end

-- Console hint label (shows when tab is selected on gamepad)
local hint = Instance.new("TextLabel")
hint.Name = "GamepadHint"
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamSemibold
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(255,255,255)
hint.TextStrokeTransparency = 0.2
hint.Text = "X/Y: Toggle"
hint.Size = UDim2.fromOffset(80, 18)
hint.AnchorPoint = Vector2.new(0, 0.5)
hint.Position = UDim2.new(1, 36, 0.5, 0) -- to the right of the tab
hint.Visible = false
hint.Parent = tray

local function updateHint()
    hint.Visible = UserInputService.GamepadEnabled and (GuiService.SelectedObject == tab)
end

GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(updateHint)
UserInputService.GamepadConnected:Connect(updateHint)
UserInputService.GamepadDisconnected:Connect(updateHint)
tab.SelectionGained:Connect(updateHint)
tab.SelectionLost:Connect(updateHint)
updateHint() -- set initial state

-- === Position Money/Flux row relative to the tray ===
local function updateTopLeftPos()
    -- sit a little above the tray's vertical center (tweak 70 to taste)
    local y = - (tray.AbsoluteSize.Y/2 + 70)
    topLeft.Position = UDim2.new(0, 10, 0.5, y)
end

-- keep it in sync while the tray animates/resizes
tray:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTopLeftPos)
updateTopLeftPos()  -- initial placement

local function bump(label)
    local sc = label:FindFirstChildOfClass("UIScale")
    if not sc then sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = label end
    local up = TweenService:Create(sc, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.15})
    local dn = TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.00})
    up:Play(); up.Completed:Connect(function() dn:Play() end)
end

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
    updateTopLeftPos() -- keep Money/Flux row aligned with the tray
end
tab.Activated:Connect(function() setOpen(not open) end)

-- Hotkeys: Keyboard "H" and Gamepad X/Y toggle the tray
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.H then
        setOpen(not open)
    elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
        if input.KeyCode == Enum.KeyCode.ButtonX or input.KeyCode == Enum.KeyCode.ButtonY then
            setOpen(not open)
        end
    end
end)

-- When a gamepad connects, auto-select the tab so D-pad works immediately
UserInputService.GamepadConnected:Connect(function()
    task.defer(function()
        if GuiService.SelectedObject == nil then
            GuiService.AutoSelectGuiEnabled = true
            GuiService.GuiNavigationEnabled = true
            GuiService.SelectedObject = tab
        end
    end)
end)

-- Scroll list for essences
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.AnchorPoint = Vector2.new(0,0)
list.Position = UDim2.fromOffset(6, 6)
list.Size = UDim2.new(1, -12, 1, -12)
list.BackgroundTransparency = 1
list.CanvasSize = UDim2.new(0,0,0,0)
list.ScrollBarThickness = 5
list.ScrollBarImageTransparency = 0.5 -- higher = lighter/fainter
list.ScrollBarImageColor3 = Color3.fromRGB(255,255,255) -- light scrollbar
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.BorderSizePixel = 0
list.Parent = tray

local vlist = Instance.new("UIListLayout", list)
vlist.Padding = UDim.new(0, 6)
vlist.HorizontalAlignment = Enum.HorizontalAlignment.Left

local function mkChip(iconId, labelText)
	local b = Instance.new("ImageButton")
    b.SelectionImageObject = invisibleSel
	b.AutoButtonColor = true
	b.BackgroundTransparency = 0.85
	b.BackgroundColor3 = Color3.fromRGB(20,20,20)
	b.Size = UDim2.fromOffset(186, 44)
	b.Image = ""
	Instance.new("UICorner", b).CornerRadius = UDim.new(0,10)
	Instance.new("UIStroke", b).Thickness = 1
    b:FindFirstChildOfClass("UIStroke").Transparency = 0.8

	local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.Size = UDim2.fromOffset(36,36)
    img.Position = UDim2.fromOffset(6,4)
    img.Image = iconId or ""
    img.Parent = b

	-- allow smooth scaling
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = img

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

	return b, txt, img
end

-- Style a currency chip to be "icon + number" with no box
local function styleCurrencyChip(chip, txt, img)
    chip.BackgroundTransparency = 1
    chip.Image = ""
    chip.AutoButtonColor = false
    chip.Size = UDim2.fromOffset(0, 56)              -- height baseline
    chip.AutomaticSize = Enum.AutomaticSize.X        -- grow width to fit text
    local s = chip:FindFirstChildOfClass("UIStroke")
    if s then s.Transparency = 1 end

    -- icon same size as essences
    img.Size = UDim2.fromOffset(48, 48)
    img.Position = UDim2.fromOffset(0, 4)

    -- amount to the RIGHT of the icon, tight gap
    txt.Parent = chip
    txt.AnchorPoint = Vector2.new(0, 0.5)
    txt.Position = UDim2.fromOffset(48 + 6, 28)      -- 6px gap from icon
    txt.Size = UDim2.fromOffset(110, 32)             -- width is enough for "999.9k"
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.TextYAlignment = Enum.TextYAlignment.Center
    txt.TextScaled = true
    txt.TextStrokeTransparency = 0.2
end

-- Currency chips (top-left)
local moneyChip, moneyTxt, moneyImg
if SHOW_CURRENCY.Money then
    moneyChip, moneyTxt, moneyImg = mkChip(ICONS.Money, "0")
    styleCurrencyChip(moneyChip, moneyTxt, moneyImg)
    moneyChip.Parent = topLeft
end

local fluxChip, fluxTxt, fluxImg
if SHOW_CURRENCY.Flux then
    fluxChip, fluxTxt, fluxImg = mkChip(ICONS.Flux, "0")
    styleCurrencyChip(fluxChip, fluxTxt, fluxImg)
    fluxChip.Parent = topLeft

     -- >>> make FLUX icon a bit bigger <<<
    fluxImg.Size = UDim2.fromOffset(56, 56)      -- was 48,48
    fluxImg.Position = UDim2.fromOffset(0, 0)    -- center vertically
    fluxTxt.Position = UDim2.fromOffset(56 + 8, 28)  -- shift number to the right
    fluxTxt.Size = UDim2.fromOffset(120, 32)     -- a touch wider for safety
end


-- Essence chips in the tray
local essenceText, essenceImg, essenceBadge = {}, {}, {}
for _, key in ipairs(SHOW) do
    local chip, txt, img = mkChip(ICONS[key], "0")
    chip.Parent = list
    essenceText[key] = txt
    essenceImg[key]  = img
    -- >>> ESSENCE overlay style <<<
    chip.Size = UDim2.fromOffset(186, 64)

    img.Size = UDim2.fromOffset(48, 48)
    img.Position = UDim2.fromOffset(8, 8)

    -- put the number ON the icon, bottom-center
    txt.Parent = img
    txt.AnchorPoint = Vector2.new(0.5, 1)
    txt.Position = UDim2.new(0.5, 0, 1, -2)
    txt.Size = UDim2.fromOffset(44, 22)
    txt.TextXAlignment = Enum.TextXAlignment.Center
    txt.TextYAlignment = Enum.TextYAlignment.Bottom
    txt.TextScaled = true
    txt.TextStrokeTransparency = 0.2  -- outline for readability

        -- >>> TIER BADGE (future) <<<
    local badge = Instance.new("TextLabel")
    badge.Name = "TierBadge"
    badge.BackgroundTransparency = 1
    badge.Font = Enum.Font.GothamBlack
    badge.TextScaled = true
    badge.TextColor3 = Color3.fromRGB(255,255,255)
    badge.TextStrokeTransparency = 0.2
    badge.Text = ""                       -- "", "II", or "III"
    badge.Size = UDim2.fromOffset(20, 14)
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -2, 0, 2) -- top-right of icon
    badge.ZIndex = (img.ZIndex or 1) + 1
    badge.Parent = img

    essenceBadge[key] = badge
end

-- Controller navigation: make each chip focusable and link it with the tab
for _, child in ipairs(list:GetChildren()) do
    if child:IsA("ImageButton") then
        child.Selectable = true
    end
end

local function firstChip()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("ImageButton") then
            return child
        end
    end
end

local fc = firstChip()
if fc then
    tab.NextSelectionRight = fc
    fc.NextSelectionLeft = tab
end

local activeTweens = setmetatable({}, {__mode = "k"}) -- weak keys

local function pulseImage(img, color)
    if not img then return end
    local scale = img:FindFirstChildOfClass("UIScale")
    if not scale then scale = Instance.new("UIScale"); scale.Scale = 1; scale.Parent = img end

    local pack = activeTweens[img]
    if pack then for _,tw in ipairs(pack) do pcall(function() tw:Cancel() end) end end

    local ring = Instance.new("ImageLabel")
    ring.BackgroundTransparency = 1
    ring.Image = img.Image
    ring.ImageColor3 = color or Color3.new(1,1,1)  -- <-- use element color
    ring.ImageTransparency = 0.5
    ring.Size = img.Size
    ring.Position = img.Position
    ring.AnchorPoint = img.AnchorPoint
    ring.ZIndex = (img.ZIndex or 1) - 1
    ring.Parent = img.Parent

    local ringScale = Instance.new("UIScale")
    ringScale.Scale = 1
    ringScale.Parent = ring

    local p0 = img.Position
    local pUp = UDim2.fromOffset(p0.X.Offset, p0.Y.Offset - 2)

    local upS   = TweenService:Create(scale,    TweenInfo.new(0.09, Enum.EasingStyle.Back,   Enum.EasingDirection.Out), {Scale = 1.15})
    local upPos = TweenService:Create(img,      TweenInfo.new(0.09, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out), {Position = pUp})
    local dnS   = TweenService:Create(scale,    TweenInfo.new(0.12, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out), {Scale = 1.00})
    local dnPos = TweenService:Create(img,      TweenInfo.new(0.12, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Position = p0})

    local ringOut = TweenService:Create(ringScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Scale = 1.35})
    local ringFade= TweenService:Create(ring,      TweenInfo.new(0.18, Enum.EasingStyle.Quad), {ImageTransparency = 1})

    activeTweens[img] = {upS, upPos, dnS, dnPos, ringOut, ringFade}

    upS:Play(); upPos:Play(); ringOut:Play(); ringFade:Play()
    upS.Completed:Connect(function()
        dnS:Play(); dnPos:Play()
    end)
    ringFade.Completed:Connect(function() if ring then ring:Destroy() end end)
end

-- Set the visible tier badge on an element: 0/1="", 2="II", 3="III"
local TIER_COLORS = { [2] = Color3.fromRGB(255,210,94), [3] = Color3.fromRGB(195,119,255) }

local function setTier(elem, t)
    local badge = essenceBadge[elem]
    if not badge then return end
    badge.Text = (t == 2 and "II") or (t == 3 and "III") or ""
    badge.TextColor3 = TIER_COLORS[t] or Color3.fromRGB(255,255,255)
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

if SHOW_CURRENCY.Money and moneyTxt then
    bindLeaderstat("Money", function(n) moneyTxt.Text = fmt(n) end)
end

-- Flux / Essence use attributes; update immediately + on change
local function bindAttr(attrName, setter)
	setter(LP:GetAttribute(attrName) or 0)
	LP:GetAttributeChangedSignal(attrName):Connect(function()
		setter(LP:GetAttribute(attrName) or 0)
	end)
end

if SHOW_CURRENCY.Flux and fluxTxt then
    bindAttr(ATTR.Flux, function(n) fluxTxt.Text = fmt(n); bump(fluxTxt) end)
end

for key, attr in pairs(ATTR) do
    if key ~= "Flux" then
        bindAttr(attr, function(n)
            if essenceText[key] then essenceText[key].Text = fmt(n); bump(essenceText[key]) end
        end)
    end
end

-- === OPTIONAL: Bind tier attributes to show "II"/"III" badges ===
-- Only add this if the server sets these attributes.
local TIER_ATTR = {
    Fire  = "EssenceTier_Fire",
    Water = "EssenceTier_Water",
    Earth = "EssenceTier_Earth",
}

for elem, attrName in pairs(TIER_ATTR) do
    local function sync()
        local v = tonumber(LP:GetAttribute(attrName)) or 0
        setTier(elem, v)
    end
    sync()
    LP:GetAttributeChangedSignal(attrName):Connect(sync)
end

-- Pulse icons when loot lands
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local RE_LootSFX = Remotes:WaitForChild("LootPickupSFX")

RE_LootSFX.OnClientEvent:Connect(function(kind, pos, payload)
    payload = payload or {}

    -- Flux pulse (colored)
    if (payload.flux or 0) > 0 and fluxImg then
        pulseImage(fluxImg, ELEM_COLOR.Flux)
    end

    -- Essence pulses (colored)
    local ess = payload.essence
    if type(ess) == "table" then
        if (ess.Fire  or 0) > 0 then pulseImage(essenceImg.Fire,  ELEM_COLOR.Fire)  end
        if (ess.Water or 0) > 0 then pulseImage(essenceImg.Water, ELEM_COLOR.Water) end
        if (ess.Earth or 0) > 0 then pulseImage(essenceImg.Earth, ELEM_COLOR.Earth) end
    end
end)


-- Start collapsed on phone
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	setOpen(false)
end
