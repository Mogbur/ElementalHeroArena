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

local function offsetYFor(model)
    if not model then return 4 end
    local _, size = model:GetBoundingBox()
    return math.max(3.5, size.Y * 0.55)
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
