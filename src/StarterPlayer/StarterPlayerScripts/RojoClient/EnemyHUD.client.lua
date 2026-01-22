-- EnemyHUD.client.lua
-- One BillboardGui HP bar per enemy tagged "Enemy".
-- Cleans itself when the enemy dies or is removed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local LOCAL = Players.LocalPlayer

local BAR_NAME = "HPGui"               -- we check this to avoid duplicates
local WIDTH, HEIGHT = 90, 10
local SPECIAL_BAR_NAME = "SpecialHUD"
local function modelPrimaryPart(m)
    return m and (m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart"))
end
-- === Debuff assets (set these) ===
local STUN_ICON_ID      = "rbxassetid://10308389229"  -- your stun icon
local PIE_HALF_RIGHT_ID = "rbxassetid://0"  -- opaque right semicircle wedge
local PIE_HALF_LEFT_ID  = "rbxassetid://0"  -- opaque left  semicircle wedge
local FIRE_ICON_ID      = "rbxassetid://91949104597643"
local SLOW_ICON_ID      = "rbxassetid://112097989485725"
local ICON_SIZE         = 24
local ICON_PAD          = 4

-- If you want the pie to "open" (reveal) over time, set this true:
local PIE_OPENS = true

-- VFX textures (set these later; leave 0 to disable)
local FIRE_PARTICLE_TEX = "rbxassetid://0"
local STUN_PARTICLE_TEX = "rbxassetid://13432139470"
local SLOW_PARTICLE_TEX = "rbxassetid://0"

local function offsetYFor(model)
    if not model then return 4 end
    local _, size = model:GetBoundingBox()
    return math.max(3.5, size.Y * 0.55)
end
local function makePieIcon(parent: Instance, iconId: string, tint: Color3)
    local holder = Instance.new("Frame")
    holder.Name = "DebuffIcon"
    holder.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
    holder.BackgroundTransparency = 1
    holder.ClipsDescendants = true
    holder.Parent = parent

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.fromScale(1,1)
    icon.Image = iconId ~= "" and iconId or STUN_ICON_ID
    icon.ImageColor3 = tint or Color3.fromRGB(120,180,255)
    icon.Parent = holder

    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.BackgroundTransparency = 1
    overlay.Size = UDim2.fromScale(1,1)
    overlay.Parent = holder

    local usePie = (PIE_HALF_RIGHT_ID ~= "rbxassetid://0") and (PIE_HALF_LEFT_ID ~= "rbxassetid://0")
    holder:SetAttribute("PieMode", usePie and "radial" or "linear")

    if usePie then
        local right = Instance.new("ImageLabel")
        right.Name = "RightHalf"
        right.BackgroundTransparency = 1
        right.Size = UDim2.fromScale(1,1)
        right.AnchorPoint = Vector2.new(0.5,0.5)
        right.Position = UDim2.fromScale(0.5,0.5)
        right.Image = PIE_HALF_RIGHT_ID
        right.ImageColor3 = Color3.new(0,0,0)
        right.ImageTransparency = 0.25
        right.Parent = overlay

        local left = Instance.new("ImageLabel")
        left.Name = "LeftHalf"
        left.BackgroundTransparency = 1
        left.Size = UDim2.fromScale(1,1)
        left.AnchorPoint = Vector2.new(0.5,0.5)
        left.Position = UDim2.fromScale(0.5,0.5)
        left.Image = PIE_HALF_LEFT_ID
        left.ImageColor3 = Color3.new(0,0,0)
        left.ImageTransparency = 0.25
        left.Visible = false
        left.Parent = overlay
    else
        local linear = Instance.new("Frame")
        linear.Name = "LinearFill"
        linear.BackgroundColor3 = Color3.new(0,0,0)
        linear.BackgroundTransparency = 0.25
        linear.BorderSizePixel = 0
        linear.AnchorPoint = Vector2.new(0.5, 0)
        linear.Position = UDim2.fromScale(0.5, 0)
        linear.Size = UDim2.fromScale(1, 0) -- grows downward
        linear.Parent = overlay
    end

    return holder
end

local function setPieFraction(holder: Instance, frac: number)
    if not holder or not holder.Parent then return end
    frac = math.clamp(frac or 0, 0, 1)
    local overlay = holder:FindFirstChild("Overlay")
    if not overlay then return end

    local mode = holder:GetAttribute("PieMode")
    if mode == "linear" then
        local linear = overlay:FindFirstChild("LinearFill")
        if linear then linear.Size = UDim2.fromScale(1, frac) end
        return
    end

    -- radial mode
    local right = overlay:FindFirstChild("RightHalf")
    local left  = overlay:FindFirstChild("LeftHalf")
    if not (right and left) then return end

    local deg = 360 * frac
    if deg <= 180 then
        right.Visible = true
        left.Visible  = false
        right.Rotation = deg
        left.Rotation  = 0
    else
        right.Visible = true
        right.Rotation = 180
        left.Visible  = true
        left.Rotation = deg - 180
    end
end

-- Create / get a tiny Debuff tray billboard for a model
local function ensureDebuffGui(enemy: Instance)
	local bb = enemy:FindFirstChild("DebuffGui")
	if bb then return bb end

	local root = modelPrimaryPart(enemy)  -- ✅ instead of manual HRP/PrimaryPart search
    if not root then return nil end

	bb = Instance.new("BillboardGui")
	bb.Name = "DebuffGui"
	bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.Size = UDim2.fromOffset(ICON_SIZE * 4 + ICON_PAD * 3, ICON_SIZE)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetYFor(enemy) + 1.2, 0)
	bb.Adornee = root
	bb.Parent = enemy

	local tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.BackgroundTransparency = 1
	tray.Size = UDim2.fromScale(1,1)
	tray.Parent = bb

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, ICON_PAD)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = tray

	return bb
end

-- Update / create stun icon for an enemy; returns nil if no stun
-- forward declare (updateStunDebuff calls this)
local disableEffectEmitter
local function updateStunDebuff(enemy: Instance)
	local untilT = tonumber(enemy:GetAttribute("StunnedUntil")) or 0
	local dur    = tonumber(enemy:GetAttribute("StunDuration")) or 0
	local start  = tonumber(enemy:GetAttribute("StunStartAt")) or (untilT - dur)

	-- ========== expired branch ==========
	if untilT <= 0 or dur <= 0 or time() >= untilT then
		local bb = enemy:FindFirstChild("DebuffGui")
		if bb then
			local icon = bb:FindFirstChild("StunIcon", true)
			if icon then icon:Destroy() end
		end
		disableEffectEmitter(enemy, "Stun")   -- ✅ turn off the swirl/sparks VFX
		return
	end
	-- ========== active branch ==========

	local bb = ensureDebuffGui(enemy); if not bb then return end
    local tray = bb:FindFirstChild("Tray"); if not tray then return end

    -- reuse holder if present; otherwise create it once
    local holder = tray:FindFirstChild("StunIcon")
    if not holder then
        holder = Instance.new("Frame")
        holder.Name = "StunIcon"
        holder.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
        holder.BackgroundTransparency = 1
        holder.Parent = tray
    end

    -- ensure (or reuse) the pie child under this holder
    local pie = holder:FindFirstChild("DebuffIcon")
    if not pie then
        local iconId = enemy:GetAttribute("StunIconId")
        pie = makePieIcon(holder, iconId and tostring(iconId) or STUN_ICON_ID, Color3.fromRGB(120,180,255))
    end

    local now = time()
    local frac = math.clamp((now - start) / math.max(0.001, dur), 0, 1)
    setPieFraction(pie, frac)

    ensureEffectEmitter(enemy, "Stun", STUN_PARTICLE_TEX, Color3.fromRGB(120,180,255)) -- ✅ keep VFX on while active
end


local function ensureEffectEmitter(enemy: Instance, key: string, textureId: string, color: Color3)
    -- returns the emitter (creates if missing), or nil if textureId==0
    if textureId == "rbxassetid://0" then return nil end
    local root = modelPrimaryPart(enemy); if not root then return nil end
    local name = "FX_"..key
    local att = root:FindFirstChild(name) :: Attachment
    if not att then
        att = Instance.new("Attachment")
        att.Name = name
        att.Parent = root
    end
    local em = att:FindFirstChildOfClass("ParticleEmitter")
    if not em then
        em = Instance.new("ParticleEmitter")
        em.Name = "Emitter"
        em.Texture = textureId
        em.Rate = 8
        em.Lifetime = NumberRange.new(0.6, 1.0)
        em.Speed = NumberRange.new(0.5, 1.5)
        em.SpreadAngle = Vector2.new(25,25)
        em.Rotation = NumberRange.new(0, 360)
        em.RotSpeed = NumberRange.new(-30, 30)
        em.LightInfluence = 0
        em.Color = ColorSequence.new(color or Color3.new(1,1,1))
        em.Parent = att
    end
    em.Enabled = true
    return em
end
-- Torch-like flame, scaled to rig size
local function ensureTorchFire(enemy: Instance)
    local root = modelPrimaryPart(enemy); if not root then return end

    -- scale by character height (so tiny mobs don’t get bonfires)
    local _, size = enemy:GetBoundingBox()
    local scale = math.clamp(size.Y / 6, 0.6, 1.8)

    -- attachment (reuse if present)
    local att = enemy:FindFirstChild("FX_Fire") :: Attachment
    if not att then
        att = Instance.new("Attachment")
        att.Name = "FX_Fire"
        att.Position = Vector3.new(0, size.Y * 0.55, 0) -- roughly chest/top
        att.Parent = root
    end

    -- main flame emitter (reuse if present)
    local em = att:FindFirstChild("Flame") :: ParticleEmitter
    if not em then
        em = Instance.new("ParticleEmitter")
        em.Name = "Flame"
        -- texture: if you set FIRE_PARTICLE_TEX it uses that; otherwise Roblox default
        if FIRE_PARTICLE_TEX ~= "rbxassetid://0" then em.Texture = FIRE_PARTICLE_TEX end

        em.Brightness = 3.5
        em.LightInfluence = 0
        em.EmissionDirection = Enum.NormalId.Top
        em.Lifetime = NumberRange.new(0.8, 1.2)
        em.Rotation = NumberRange.new(0, 360)
        em.RotSpeed = NumberRange.new(-50, 50)
        em.SpreadAngle = Vector2.new(20, 20)
        em.ZOffset = 0

        -- color from yellow → orange → red
        em.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,235,140)),
            ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255,155,70)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(180,60,20)),
        })

        -- soft fade in/out
        em.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.00, 0.25),
            NumberSequenceKeypoint.new(0.10, 0.00),
            NumberSequenceKeypoint.new(0.80, 0.25),
            NumberSequenceKeypoint.new(1.00, 1.00),
        })

        em.Parent = att
    end

    -- per-frame tunables based on scale (safe to reassign)
    em.Rate  = math.floor(10 * scale)                  -- how many particles per sec
    em.Speed = NumberRange.new(0.6 * scale, 2.0 * scale)
    em.Acceleration = Vector3.new(0, 2.0 * scale, 0)   -- rise
    em.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 0.6 * scale),
        NumberSequenceKeypoint.new(0.25, 1.2 * scale),
        NumberSequenceKeypoint.new(1.00, 0.0),
    })

    em.Enabled = true
end

disableEffectEmitter = function(enemy: Instance, key: string)
    local att = enemy:FindFirstChild("FX_"..key, true)  -- recursive search
    if att and att:IsA("Attachment") then
        for _, child in ipairs(att:GetChildren()) do
            if child:IsA("ParticleEmitter") then
                child.Enabled = false
            end
        end
    end
end

local function updateFireDebuff(enemy: Instance)
    local untilT = tonumber(enemy:GetAttribute("FireUntil")) or 0
    local dur    = tonumber(enemy:GetAttribute("FireDuration")) or 0
    local start  = tonumber(enemy:GetAttribute("FireStartAt")) or (untilT - dur)
    local now = time()

    if untilT <= 0 or dur <= 0 or now >= untilT then
        local bb = enemy:FindFirstChild("DebuffGui")
        if bb then
            local tray = bb:FindFirstChild("Tray")
            local icon = tray and tray:FindFirstChild("FireIcon")
            if icon then icon:Destroy() end
        end
        disableEffectEmitter(enemy, "Fire")
        return
    end

    local bb = ensureDebuffGui(enemy); if not bb then return end

    local tray = bb:FindFirstChild("Tray")
    if not tray then return end
    local holder = tray:FindFirstChild("FireIcon")
    if not holder then
        holder = Instance.new("Frame")
        holder.Name = "FireIcon"
        holder.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
        holder.BackgroundTransparency = 1
        holder.Parent = tray
        local iconId = enemy:GetAttribute("FireIconId")
        local pie = makePieIcon(holder, iconId and tostring(iconId) or FIRE_ICON_ID, Color3.fromRGB(255, 150, 80))
        pie.Name = "DebuffIcon" -- (for clarity)
    end

    local frac = math.clamp((now - start) / math.max(0.001, dur), 0, 1)
    setPieFraction(holder:FindFirstChild("DebuffIcon"), PIE_OPENS and (1 - frac) or frac)

    -- VFX
    ensureTorchFire(enemy)
    ensureEffectEmitter(enemy, "Fire", FIRE_PARTICLE_TEX, Color3.fromRGB(255,140,60))
end

local function updateSlowDebuff(enemy: Instance)
    local untilT = tonumber(enemy:GetAttribute("SlowUntil")) or 0
    local dur    = tonumber(enemy:GetAttribute("SlowDuration")) or 0
    local start  = tonumber(enemy:GetAttribute("SlowStartAt")) or (untilT - dur)
    local now = time()

    if untilT <= 0 or dur <= 0 or now >= untilT then
        local bb = enemy:FindFirstChild("DebuffGui")
        if bb then
            local tray = bb:FindFirstChild("Tray")
            local icon = tray and tray:FindFirstChild("SlowIcon")
            if icon then icon:Destroy() end
        end
        disableEffectEmitter(enemy, "Slow")
        return
    end

    local bb = ensureDebuffGui(enemy); if not bb then return end
    local tray = bb:FindFirstChild("Tray")
    if not tray then return end
    local holder = tray:FindFirstChild("SlowIcon")
    if not holder then
        holder = Instance.new("Frame")
        holder.Name = "SlowIcon"
        holder.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
        holder.BackgroundTransparency = 1
        holder.Parent = tray
        local iconId = enemy:GetAttribute("SlowIconId")
        local pie = makePieIcon(holder, iconId and tostring(iconId) or SLOW_ICON_ID, Color3.fromRGB(160,200,255))
        pie.Name = "DebuffIcon"
    end

    local frac = math.clamp((now - start) / math.max(0.001, dur), 0, 1)
    setPieFraction(holder:FindFirstChild("DebuffIcon"), PIE_OPENS and (1 - frac) or frac)

    -- VFX
    ensureEffectEmitter(enemy, "Slow", SLOW_PARTICLE_TEX, Color3.fromRGB(140,200,255))
end

local function ensureMiniBossBar(enemy: Instance)
    if not enemy or not enemy.Parent then return end
    if enemy:FindFirstChild(SPECIAL_BAR_NAME) then return end

    local hum  = enemy:FindFirstChildOfClass("Humanoid")
    local root = modelPrimaryPart(enemy)
    if not (hum and root) then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = SPECIAL_BAR_NAME
    bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    bb.AlwaysOnTop = true
    bb.MaxDistance = 250
    bb.Size = UDim2.fromOffset(160, 40)
    bb.StudsOffsetWorldSpace = Vector3.new(0, offsetYFor(enemy), 0)
    bb.Adornee = root
    bb.Parent = enemy

    local rootF = Instance.new("Frame")
    rootF.BackgroundTransparency = 1
    rootF.Size = UDim2.fromScale(1,1)
    rootF.Parent = bb

    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Vertical
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.Padding = UDim.new(0, 2)
    list.Parent = rootF

    -- HP row (16px)
    local HPBack = Instance.new("Frame")
    HPBack.Name = "HPBack"
    HPBack.Size = UDim2.new(1, -2, 0, 16)
    HPBack.BackgroundColor3 = Color3.fromRGB(36,36,36)
    HPBack.BorderSizePixel = 0
    HPBack.Parent = rootF
    local c1 = Instance.new("UICorner", HPBack) c1.CornerRadius = UDim.new(0,6)
    local s1 = Instance.new("UIStroke", HPBack) s1.Thickness = 1 s1.Color = Color3.fromRGB(0,0,0) s1.Transparency = 0.35

    local HPFill = Instance.new("Frame")
    HPFill.Name = "HPFill"
    HPFill.Size = UDim2.new(0, 0, 1, 0)
    HPFill.BackgroundColor3 = Color3.fromRGB(90,220,100)
    HPFill.BorderSizePixel = 0
    HPFill.Parent = HPBack
    local c2 = Instance.new("UICorner", HPFill) c2.CornerRadius = UDim.new(0,6)

    local HPText = Instance.new("TextLabel")
    HPText.Name = "HPText"
    HPText.BackgroundTransparency = 1
    HPText.Size = UDim2.fromScale(1,1)
    HPText.Font = Enum.Font.GothamBold
    HPText.TextScaled = true
    HPText.TextColor3 = Color3.fromRGB(255,255,255)
    HPText.TextStrokeTransparency = 0.2
    HPText.Text = "0 / 0"
    HPText.Parent = HPBack

    -- thin shield row (8px) – hidden unless shield > 0
    local SBack = Instance.new("Frame")
    SBack.Name = "SBack"
    SBack.Size = UDim2.new(1, -2, 0, 8)
    SBack.BackgroundColor3 = Color3.fromRGB(26,26,30)
    SBack.BorderSizePixel = 0
    SBack.Parent = rootF
    local c3 = Instance.new("UICorner", SBack) c3.CornerRadius = UDim.new(0,4)
    local s3 = Instance.new("UIStroke", SBack) s3.Thickness = 1 s3.Color = Color3.fromRGB(0,0,0) s3.Transparency = 0.35

    local SFill = Instance.new("Frame")
    SFill.Name = "SFill"
    SFill.Size = UDim2.new(0, 0, 1, 0)
    SFill.BackgroundColor3 = Color3.fromRGB(80,160,255)
    SFill.BorderSizePixel = 0
    SFill.Parent = SBack
    local c4 = Instance.new("UICorner", SFill) c4.CornerRadius = UDim.new(0,4)

    -- updater
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not enemy.Parent or hum.Health <= 0 then
            if conn then conn:Disconnect() end
            if bb then bb:Destroy() end
            return
        end
        -- keep debuff billboard aligned and update stun pie
        local dbg = enemy:FindFirstChild("DebuffGui")
        if dbg then
            dbg.Adornee = modelPrimaryPart(enemy) or dbg.Adornee
            local oy = offsetYFor(enemy) + 1.2
            if math.abs(dbg.StudsOffsetWorldSpace.Y - oy) > 0.05 then
                dbg.StudsOffsetWorldSpace = Vector3.new(0, oy, 0)
            end
        end
        updateStunDebuff(enemy)
        updateFireDebuff(enemy)
        updateSlowDebuff(enemy)
        local hp   = math.max(0, math.floor(hum.Health + 0.5))
        local mx   = math.max(1, math.floor(hum.MaxHealth + 0.5))
        local frac = math.clamp(hp / mx, 0, 1)
        HPFill.Size = UDim2.fromScale(frac, 1)
        HPText.Text = string.format("%d / %d", hp, mx)

        -- optional shield attribute on the enemy (matches hero logic, shows if > 0)
        local sh = math.max(0, math.floor((enemy:GetAttribute("ShieldHP") or 0) + 0.5))
        local sfrac = math.clamp(sh / mx, 0, 1)
        SFill.Size = UDim2.fromScale(sfrac, 1)
        SBack.Visible = (sh > 0)
        -- keep the bar pinned nicely even if the rig's height changes
        local oy = offsetYFor(enemy)
        if math.abs(bb.StudsOffsetWorldSpace.Y - oy) > 0.05 then
            bb.StudsOffsetWorldSpace = Vector3.new(0, oy, 0)
        end

        -- if the model swapped its primary/HRP, reattach the adornee
        local cur = modelPrimaryPart(enemy)
        if cur and bb.Adornee ~= cur then
            bb.Adornee = cur
        end
    end)

    enemy.AncestryChanged:Connect(function(_, parent)
        if not parent then
            if conn then conn:Disconnect() end
            if bb then bb:Destroy() end
        end
    end)
end

-- Prefer the visible Body; fall back to Head or HRP/PrimaryPart.
local function getBarAnchor(model: Model)
	return model:FindFirstChild("Body")
		or model:FindFirstChild("Head")
		or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
end

local function ensureBar(enemy: Instance)
	if not enemy or not enemy.Parent then return end

    -- hero-style HUD for minibosses
    local rank  = tostring(enemy:GetAttribute("Rank") or "")
    local shud  = tostring(enemy:GetAttribute("SpecialHUD") or "")
    if rank == "MiniBoss" or shud == "MiniBoss" then
        -- don’t duplicate if it already exists
        if not enemy:FindFirstChild(SPECIAL_BAR_NAME) then
            ensureMiniBossBar(enemy)  -- <<— requires the helper defined above
        end
        return
    end

	-- prevent duplicate simple bars
	if enemy:FindFirstChild(BAR_NAME) then return end

	local hum  = enemy:FindFirstChildOfClass("Humanoid")
	local anchor = getBarAnchor(enemy)
	if not (hum and anchor) then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = BAR_NAME
	bb.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	-- put the bar a bit above the anchor's top
	local h = (anchor:IsA("BasePart") and anchor.Size.Y) or 2
	bb.StudsOffsetWorldSpace = Vector3.new(0, (h * 0.5) + 1.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Adornee = anchor
	bb.Parent = enemy  -- keep under model so our duplicate check works

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1,1)
	bg.BackgroundColor3 = Color3.fromRGB(25,25,25)
	bg.BackgroundTransparency = 0.35
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0,0)
	fill.Position = UDim2.fromScale(0,0)
	fill.Size = UDim2.fromScale(1,1)
	fill.BackgroundColor3 = Color3.fromRGB(95, 220, 110)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local uic = Instance.new("UICorner")
	uic.CornerRadius = UDim.new(0,4)
	uic.Parent = bg
	local uic2 = Instance.new("UICorner")
	uic2.CornerRadius = UDim.new(0,4)
	uic2.Parent = fill

	-- updater
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not enemy.Parent or hum.Health <= 0 then
			if conn then conn:Disconnect() end
			if bb then bb:Destroy() end
			return
		end
        -- keep debuff billboard aligned and update stun pie
        local dbg = enemy:FindFirstChild("DebuffGui")
        if dbg then
            dbg.Adornee = modelPrimaryPart(enemy) or dbg.Adornee
            local oy = offsetYFor(enemy) + 1.2
            if math.abs(dbg.StudsOffsetWorldSpace.Y - oy) > 0.05 then
                dbg.StudsOffsetWorldSpace = Vector3.new(0, oy, 0)
            end
        end
        updateStunDebuff(enemy)
        updateFireDebuff(enemy)
        updateSlowDebuff(enemy)
		local frac = 0
		if hum.MaxHealth > 0 then
			frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		end
		fill.Size = UDim2.fromScale(frac, 1)
	end)

	enemy.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if conn then conn:Disconnect() end
			if bb then bb:Destroy() end
		end
	end)
end


-- Existing enemies on join
for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
	ensureBar(e)
end

-- New enemies
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(e)
	ensureBar(e)
end)
