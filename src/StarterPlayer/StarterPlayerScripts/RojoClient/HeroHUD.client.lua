-- HeroHUD.client.lua
-- Solid, non-drifting hero bars (HP + thin blue Shield), numbers inside, element icon.
-- Works only for the local player's hero. Enemies are handled by EnemyHUD.

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local lp          = Players.LocalPlayer
-- put these near the top of the file, before refreshBuffs()
local attachedHero, attachedPlot, attachedHum
local bb, HPBack, HPFill, HPText, Icon, SBack, SFill, SText, BuffRow, I_OC, I_AG, I_SW
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

local function segId(plot)
	local w = tonumber(plot and plot:GetAttribute("CurrentWave")) or 1
	return (w - 1) // 5
end

local function buffsActive()
	if not (attachedPlot and attachedHero) then return false end
	local curSeg  = segId(attachedPlot)
	local utilSeg = tonumber(attachedPlot:GetAttribute("UtilExpiresSegId")) or -999
	local oc      = tonumber(attachedPlot:GetAttribute("Util_OverchargePct")) or 0
	local sw      = tonumber(attachedPlot:GetAttribute("Util_SecondWindLeft")) or 0
	local aegSeg  = tonumber(attachedPlot:GetAttribute("Util_AegisSeg")) or -999
	local shield  = tonumber(attachedHero:GetAttribute("ShieldHP")) or 0
	local sameSeg = (utilSeg == curSeg)
	local noSeg   = (utilSeg == -999)

	return ((oc > 0 or sw > 0) and (sameSeg or noSeg))
	       or (aegSeg == curSeg)
	       or (shield > 0)
end

local function segIdFromWave(w) w = tonumber(w) or 1; return math.floor((w-1)/5) end

local GUI_NAME = "HeroHUD"

local function nukeOtherBars(hero: Model, keep: Instance?)
	if not hero then return end
	local function sweep(container)
		if not container then return end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("BillboardGui") then
				local n = inst.Name
				-- remove any stray hero bars we might have used in older builds
				if n == GUI_NAME or n == "HeroBarsGui" or n == "HeroBillboard" then
					if inst ~= keep then inst:Destroy() end
				end
			end
		end
	end
	sweep(hero)
	local hrp = primaryPart(hero)
	sweep(hrp)
end

local function refreshBuffs()
    if not (BuffRow and I_OC and I_AG and I_SW) then return end
    if not (attachedPlot and attachedHero) then
        BuffRow.Visible = false
        return
    end

    local segNow  = segIdFromWave(attachedPlot:GetAttribute("CurrentWave") or 1)
    local utilSeg = tonumber(attachedPlot:GetAttribute("UtilExpiresSegId")) or -999
    local ocPct   = tonumber(attachedPlot:GetAttribute("Util_OverchargePct")) or 0
    local swLeft  = tonumber(attachedPlot:GetAttribute("Util_SecondWindLeft")) or 0
    local aegSeg  = tonumber(attachedPlot:GetAttribute("Util_AegisSeg")) or -999
    local shp     = tonumber(attachedHero:GetAttribute("ShieldHP")) or 0
	-- If UtilExpiresSegId isn't present, still show icons whenever the buff is non-zero.
	local sameSeg = (utilSeg == segNow)
	local noSeg   = (utilSeg == -999)

	I_OC.Visible = (ocPct > 0) and (sameSeg or noSeg)
	I_SW.Visible = (swLeft > 0) and (sameSeg or noSeg)
	I_AG.Visible = (shp > 0) or (aegSeg == segNow)

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
-- Optional pictures for the tiny buff icons (emoji fallback if blank)
local BUFF_IMAGES = {
    OC = "",  -- Overcharge (⚡) e.g. "rbxassetid://12345"
    AG = "",  -- Aegis/Shield (🛡) put whatever you like
    SW = "",  -- Second Wind (♥)
}

-- ===== UI BUILD =====
local function buildGui()
	local bb = Instance.new("BillboardGui")
	bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bb.Name = GUI_NAME            -- <= single source of truth
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
	BuffRow.Size = UDim2.new(1, 0, 0, 14)      -- was 10 → a hair taller
	BuffRow.BackgroundTransparency = 1         -- no background
	BuffRow.Parent = root
	BuffRow.LayoutOrder = -1
	local hlist = Instance.new("UIListLayout", BuffRow)
	hlist.FillDirection = Enum.FillDirection.Horizontal
	hlist.Padding = UDim.new(0, 3)             -- a bit more breathing room
	hlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hlist.VerticalAlignment   = Enum.VerticalAlignment.Center
	BuffRow.ZIndex = 5

	-- one icon factory: Image + emoji text fallback, no background
	local function mkI(emoji, key)
		local holder = Instance.new("Frame")
		holder.Name = "Buff_"..key
		holder.Size = UDim2.fromOffset(14, 14) -- a smidge bigger
		holder.BackgroundTransparency = 1
		holder.Visible = false
		holder.Parent = BuffRow
		holder.ZIndex = 6                 -- <— add this
		holder.ClipsDescendants = false   -- safety

		local img = Instance.new("ImageLabel")
		img.ZIndex = 6
		img.Name = "Img"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1,1)
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = holder

		local txt = Instance.new("TextLabel")
		txt.ZIndex = 7
		txt.Name = "Txt"
		txt.BackgroundTransparency = 1
		txt.Size = UDim2.fromScale(1,1)
		txt.Font = Enum.Font.GothamBold
		txt.TextScaled = true
		txt.TextColor3 = Color3.fromRGB(230,235,255)
		txt.Text = emoji
		txt.Parent = holder

		return holder
	end

	local I_OC = mkI("⚡","OC")
	local I_AG = mkI("🛡","AG")
	local I_SW = mkI("♥","SW")

	local function applyBuffArt()
		local map = { OC = I_OC, AG = I_AG, SW = I_SW }
		for key, frame in pairs(map) do
			local id  = BUFF_IMAGES[key]
			local img = frame:FindFirstChild("Img")
			local txt = frame:FindFirstChild("Txt")
			if type(id) == "string" and id ~= "" then
				img.Image = id
				img.Visible = true
				if txt then txt.Visible = false end
			else
				if img then img.Image = "" end
				if txt then txt.Visible = true end
			end
		end
	end

	-- HP BAR (16 px)
	local HPBack = Instance.new("Frame")
	HPBack.Name = "HPBack"
	HPBack.Size = UDim2.new(1, -2, 0, 16)
	HPBack.BackgroundColor3 = Color3.fromRGB(36,36,36)
	HPBack.BorderSizePixel = 0
	HPBack.Parent = root
	local hpCorner = Instance.new("UICorner", HPBack) hpCorner.CornerRadius = UDim.new(0, 6)
	local hpStroke = Instance.new("UIStroke", HPBack) hpStroke.Thickness = 1 hpStroke.Color = Color3.fromRGB(0,0,0) hpStroke.Transparency = 0.35

	-- ELEMENT ICON (tiny, left inside HP bar)
	local Icon = Instance.new("ImageLabel")
	Icon.Name = "Icon"
	Icon.AnchorPoint = Vector2.new(0,0.5)
	Icon.Position = UDim2.fromOffset(3, 8)
	Icon.Size = UDim2.fromOffset(14, 14)   -- bump to 15/16 if you want bigger
	Icon.BackgroundTransparency = 1
	Icon.ScaleType = Enum.ScaleType.Fit
	Icon.ZIndex = 5
	Icon.Parent = HPBack
	Instance.new("UICorner", Icon).CornerRadius = UDim.new(1,0)

	-- emoji fallback layered on top of the image
	local IconText = Instance.new("TextLabel")
	IconText.Name = "IconText"
	IconText.BackgroundTransparency = 1
	IconText.Size = UDim2.fromScale(1,1)
	IconText.Font = Enum.Font.GothamBold
	IconText.TextScaled = true
	IconText.TextColor3 = Color3.fromRGB(255,255,255)
	IconText.Visible = false
	IconText.Parent = Icon

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

	-- at the very end of buildGui()
	applyBuffArt()
	return bb, HPBack, HPFill, HPText, Icon, SBack, SFill, SText, BuffRow, I_OC, I_AG, I_SW
end

-- ===== main attach/update =====
bb, HPBack, HPFill, HPText, Icon, SBack, SFill, SText, BuffRow, I_OC, I_AG, I_SW = buildGui()
local lastAdornee, lastOffsetY
local _plotBlessingConn

local function normalizeElem(e)
	e = tostring(e or "Neutral")
	if e == "Fire" or e == "Water" or e == "Earth" then return e end
	return "Neutral"
end

-- blessing-driven element (from the plot only)
local function elementFromBlessing(plot)
	if not plot then return "Neutral" end
	local curSeg = segIdFromWave(plot:GetAttribute("CurrentWave") or 1)
	local bElem  = plot:GetAttribute("BlessingElem")
	local bSeg   = tonumber(plot:GetAttribute("BlessingExpiresSegId")) or -999
	if bElem and bSeg == curSeg then
		return normalizeElem(bElem) -- Fire/Water/Earth while Blessing is active
	end
	return normalizeElem(plot:GetAttribute("LastElement")) -- fallback
end

local function setElementIcon(plot)
    local e = elementFromBlessing(plot)
    local ok = ELEMENT_ICON[e] and ELEMENT_ICON[e] ~= ""
    local txt = Icon:FindFirstChild("IconText")
    if ok then
        Icon.Image = ELEMENT_ICON[e]
        if txt then txt.Visible = false end
    else
        Icon.Image = ""
        if txt then
            txt.Text = ELEMENT_EMOJI[e] or "⬤"
            txt.Visible = true
        end
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
	nukeOtherBars(h, bb) -- remove any stray old bars
	bb.Parent = h
	bb.Adornee = pp
	-- in attach(), after setting attachedPlot/attachedHero:
	if attachedPlot then
		for _, n in ipairs({
			"BlessingElem","BlessingExpiresSegId","CurrentWave",
			"Util_OverchargePct","Util_SecondWindLeft","Util_AegisSeg","UtilExpiresSegId"
		}) do
			attachedPlot:GetAttributeChangedSignal(n):Connect(function()
				refreshBuffs()
				setElementIcon(attachedPlot)
			end)
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

-- show/hide: show while fighting OR if any buffs are active at idle
local function updateVisibility()
	local show = false
	if attachedHero then
		show = (attachedHero:GetAttribute("BarsVisible") == 1) or buffsActive()
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
