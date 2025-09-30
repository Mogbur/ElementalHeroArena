-- HeroHUD.client.lua
-- Solid, non-drifting hero bars (HP + thin blue Shield), numbers inside, element icon.
-- Works only for the local player's hero. Enemies are handled by EnemyHUD.

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local lp          = Players.LocalPlayer

local function primaryPart(m)
	return m and (m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart"))
end
local function humanoid(m)
	local h = m and m:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then return h end
	return m and m:FindFirstChildOfClass("Humanoid") -- allow 0 to show 0/Max
end

local function myPlot()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _,p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and p:GetAttribute("OwnerUserId") == lp.UserId then
			return p
		end
	end
end

local function segIdFromWave(w) w = tonumber(w) or 1; return math.floor((w-1)/5) end

local function refreshBuffs()
    if not (attachedPlot and attachedHero) then BuffRow.Visible=false; return end
    local segNow = segIdFromWave(attachedPlot:GetAttribute("CurrentWave") or 1)
    local ocPct  = tonumber(attachedPlot:GetAttribute("Util_OverchargePct")) or 0
    local utilSeg= tonumber(attachedPlot:GetAttribute("UtilExpiresSegId")) or -999
    local swLeft = tonumber(attachedPlot:GetAttribute("Util_SecondWindLeft")) or 0
    local shp    = tonumber(attachedHero:GetAttribute("ShieldHP")) or 0

    I_OC.Visible = (ocPct > 0) and (utilSeg == segNow)
    I_SW.Visible = (swLeft > 0) and (utilSeg == segNow)
    I_AG.Visible = (shp   > 0)

    BuffRow.Visible = (I_OC.Visible or I_SW.Visible or I_AG.Visible)
end

local function myHero()
	local p = myPlot()
	if not p then return end
	local h = p:FindFirstChild("Hero", true)
	if h and h:IsA("Model") then return h, p end
end

-- compute billboard offset above the hero’s head from bounding box
local function offsetYFor(model)
	if not model then return 4 end
	local _, size = model:GetBoundingBox()
	return math.max(3.5, size.Y * 0.55) -- consistent headspace on any rig
end

-- Tiny element “icon” without relying on external images (safe fallback).
-- If you add images later, set `ICON.Image` with rbxassetids here.
local ELEMENT_EMOJI = {
	Fire   = "🔥",
	Water  = "💧",
	Earth  = "🪨",
	Neutral= "⬤",
}
local ELEMENT_ICON = {
	Fire    = "rbxassetid://138197195310947",
	Water   = "rbxassetid://102519339667737",
	Earth   = "rbxassetid://16944709510",
	Neutral = "rbxassetid://742820149",
}

-- ===== UI BUILD =====
local function buildGui()
	local bb = Instance.new("BillboardGui")
	bb.Name = "HeroHUD"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(160, 40)  -- total height: HP 16 + pad 2 + Shield 8 + pad 2
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	bb.MaxDistance = 250

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1,1)
	root.Parent = bb

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 2)
	list.Parent = root

	-- BUFF ROW (top, tiny)
	local BuffRow = Instance.new("Frame")
	BuffRow.Name = "BuffRow"
	BuffRow.Size = UDim2.new(1, 0, 0, 10)
	BuffRow.BackgroundTransparency = 1
	BuffRow.Parent = root
	BuffRow.LayoutOrder = -1 -- sit above HP bar
	local hlist = Instance.new("UIListLayout", BuffRow)
	hlist.FillDirection = Enum.FillDirection.Horizontal
	hlist.Padding = UDim.new(0, 2)
	hlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hlist.VerticalAlignment   = Enum.VerticalAlignment.Center
	local function mkI(txt)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromOffset(16, 10)
		t.BackgroundColor3 = Color3.fromRGB(36,42,64)
		t.BackgroundTransparency = 0.25
		t.TextColor3 = Color3.fromRGB(230,235,255)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.Text = txt
		t.Visible = false
		t.Parent = BuffRow
		return t
	end
	local I_OC = mkI("⚡")
	local I_AG = mkI("🛡")
	local I_SW = mkI("♥")

	-- HP BAR (16 px)
	local HPBack = Instance.new("Frame")
	HPBack.Name = "HPBack"
	HPBack.Size = UDim2.new(1, -2, 0, 16)
	HPBack.BackgroundColor3 = Color3.fromRGB(36,36,36)
	HPBack.BorderSizePixel = 0
	HPBack.Parent = root
	local hpCorner = Instance.new("UICorner", HPBack) hpCorner.CornerRadius = UDim.new(0, 6)
	local hpStroke = Instance.new("UIStroke", HPBack) hpStroke.Thickness = 1 hpStroke.Color = Color3.fromRGB(0,0,0) hpStroke.Transparency = 0.35

    -- icon holder (left inside HP bar) - IMAGE
    local Icon = Instance.new("ImageLabel")
    Icon.Name = "Icon"
    Icon.AnchorPoint = Vector2.new(0,0.5)
    Icon.Position = UDim2.fromOffset(3, 8)
    Icon.Size = UDim2.fromOffset(14, 14)
    Icon.BackgroundTransparency = 1
    Icon.ScaleType = Enum.ScaleType.Fit
    Icon.ZIndex = 5
    Icon.Parent = HPBack
    local icCorner = Instance.new("UICorner", Icon) icCorner.CornerRadius = UDim.new(1,0)

	-- HP fill
	local HPFill = Instance.new("Frame")
	HPFill.Name = "HPFill"
	HPFill.Size = UDim2.new(0, 0, 1, 0)
	HPFill.BackgroundColor3 = Color3.fromRGB(90, 220, 100)
	HPFill.BorderSizePixel = 0
	HPFill.Parent = HPBack
	local hpFillCorner = Instance.new("UICorner", HPFill) hpFillCorner.CornerRadius = UDim.new(0, 6)

	-- HP text (centered; padded so it doesn’t sit under the icon)
	local HPText = Instance.new("TextLabel")
	HPText.Name = "HPText"
	HPText.BackgroundTransparency = 1
	HPText.Size = UDim2.fromScale(1,1)
	HPText.Position = UDim2.fromOffset(0,0)
	HPText.Font = Enum.Font.GothamBold
	HPText.TextScaled = true
	HPText.TextColor3 = Color3.fromRGB(255,255,255)
	HPText.TextStrokeTransparency = 0.2
	HPText.Text = "0 / 0"
	HPText.Parent = HPBack
	local pad = Instance.new("UIPadding", HPText)
	pad.PaddingLeft = UDim.new(0, 18)

	-- SHIELD BAR (8 px) – thin, directly under HP
	local SBack = Instance.new("Frame")
	SBack.Name = "SBack"
	SBack.Size = UDim2.new(1, -2, 0, 8)
	SBack.BackgroundColor3 = Color3.fromRGB(26,26,30)
	SBack.BorderSizePixel = 0
	SBack.Parent = root
	local sCorner = Instance.new("UICorner", SBack) sCorner.CornerRadius = UDim.new(0, 4)
	local sStroke = Instance.new("UIStroke", SBack) sStroke.Thickness = 1 sStroke.Color = Color3.fromRGB(0,0,0) sStroke.Transparency = 0.35

	local SFill = Instance.new("Frame")
	SFill.Name = "SFill"
	SFill.Size = UDim2.new(0, 0, 1, 0)
	SFill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
	SFill.BorderSizePixel = 0
	SFill.Parent = SBack
	local sFillCorner = Instance.new("UICorner", SFill) sFillCorner.CornerRadius = UDim.new(0, 4)

	local SText = Instance.new("TextLabel")
	SText.Name = "SText"
	SText.BackgroundTransparency = 1
	SText.Size = UDim2.fromScale(1,1)
	SText.Font = Enum.Font.GothamBold
	SText.TextScaled = true
	SText.TextColor3 = Color3.fromRGB(230,240,255)
	SText.TextStrokeTransparency = 0.45
	SText.Text = ""
	SText.Parent = SBack

	return bb, HPBack, HPFill, HPText, Icon, SBack, SFill, SText
end

-- ===== main attach/update =====
local bb, HPBack, HPFill, HPText, Icon, SBack, SFill, SText = buildGui()
local attachedHero, attachedPlot, attachedHum
local lastAdornee, lastOffsetY
local _plotBlessingConn

local function normalizeElem(e)
	e = tostring(e or "Neutral")
	if e == "Fire" or e == "Water" or e == "Earth" then return e end
	return "Neutral"
end

-- blessing-driven element (from the plot only)
local function elementFromBlessing(plot)
	return normalizeElem(plot and plot:GetAttribute("LastElement"))
end

local function setElementIcon(plot)
	local e = elementFromBlessing(plot)
	if ELEMENT_ICON[e] and ELEMENT_ICON[e] ~= "" then
		Icon.Image = ELEMENT_ICON[e]
	else
		Icon.Image = "" -- no image? fall back to emoji look
		-- quick emoji fallback: tint and show a tiny dot using a 9-slice? simplest is:
		-- (if you want a text fallback, convert Icon back to a TextLabel; otherwise just leave image empty)
	end
end

local function attach()
	local h, p = myHero()
	if not h then
		if bb.Parent then bb.Parent = nil end
		attachedHero, attachedPlot, attachedHum = nil, nil, nil
		return
	end

	local hum = humanoid(h)
	local pp = primaryPart(h)
	if not pp then return end

	attachedHero, attachedPlot, attachedHum = h, p, hum
    -- react to blessing swaps
    if _plotBlessingConn then _plotBlessingConn:Disconnect() end
    if attachedPlot then
        _plotBlessingConn = attachedPlot:GetAttributeChangedSignal("LastElement"):Connect(function()
            setElementIcon(attachedPlot)
        end)
    end
	bb.Parent = h
	bb.Adornee = pp
	-- in attach(), after setting attachedPlot/attachedHero:
	if attachedPlot then
		for _,n in ipairs({"Util_OverchargePct","Util_SecondWindLeft","UtilExpiresSegId","CurrentWave"}) do
			attachedPlot:GetAttributeChangedSignal(n):Connect(refreshBuffs)
		end
	end
	if attachedHero then
		attachedHero:GetAttributeChangedSignal("ShieldHP"):Connect(refreshBuffs)
	end
	refreshBuffs()

	-- vertically anchor once and refresh occasionally
	local oy = offsetYFor(h)
	bb.StudsOffsetWorldSpace = Vector3.new(0, oy, 0)
	lastAdornee, lastOffsetY = pp, oy

	-- element icon styling
	setElementIcon(p)
end

-- show/hide respects BarsVisible (default hidden while idle)
local function updateVisibility()
	local show = false
	if attachedHero then
		if attachedHero:GetAttribute("BarsVisible") == 1 then
			show = true
		end
	end
	bb.Enabled = show
end

local function clamp01(x) return (x < 0 and 0) or (x > 1 and 1) or x end

local function updateNumbers()
	if not (attachedHum and attachedHum.Parent) then return end

	local hp = math.max(0, math.floor(attachedHum.Health + 0.5))
	local mx = math.max(1, math.floor(attachedHum.MaxHealth + 0.5))
	local ratio = clamp01(hp / mx)
	HPFill.Size = UDim2.new(ratio, 0, 1, 0)
	HPText.Text = string.format("%d / %d", hp, mx)

	-- make the green a bit “danger” tinted at low HP
	if ratio <= 0.25 then
		HPFill.BackgroundColor3 = Color3.fromRGB(230,80,80)
	else
		HPFill.BackgroundColor3 = Color3.fromRGB(90,220,100)
	end

	-- shield reads from attributes and is scaled to MaxHealth so it lines up visually
	local sh = math.max(0, math.floor((attachedHero:GetAttribute("ShieldHP") or 0) + 0.5))
	local shRatio = clamp01(sh / mx)
	SFill.Size = UDim2.new(shRatio, 0, 1, 0)
	if sh > 0 then
		SBack.Visible = true
		SText.Text = tostring(sh)
	else
		SBack.Visible = false
		SText.Text = ""
	end
end

-- gentle refresh of offset so it stays pinned even if rig height changes
local tAccum = 0
RunService.Heartbeat:Connect(function(dt)
	if not attachedHero or not attachedHero.Parent then
		attach() -- try again until the hero exists
		return
	end

	-- Visibility + numbers every frame (cheap)
	updateVisibility()
	updateNumbers()
	refreshBuffs()

	-- Re-check position ~4x a second
	tAccum += dt
	if tAccum >= 0.25 then
		tAccum = 0
		local pp = primaryPart(attachedHero)
		if bb.Adornee ~= pp then bb.Adornee = pp end
		local oy = offsetYFor(attachedHero)
		if math.abs(oy - (lastOffsetY or 0)) > 0.05 then
			bb.StudsOffsetWorldSpace = Vector3.new(0, oy, 0)
			lastOffsetY = oy
		end
		-- element might change between segments (Blessing/forge swaps)
		setElementIcon(attachedPlot)
	end
end)

-- first attach
attach()

-- also reattach when character/plot gets replaced
lp.CharacterAdded:Connect(function() task.wait(0.2); attach() end)
