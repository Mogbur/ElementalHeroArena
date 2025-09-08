-- EnemyHUD.client.lua
-- One BillboardGui HP bar per enemy tagged "Enemy".
-- Cleans itself when the enemy dies or is removed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local LOCAL = Players.LocalPlayer

local BAR_NAME = "HPGui"               -- we check this to avoid duplicates
local WIDTH, HEIGHT = 90, 10

-- Prefer the visible Body; fall back to Head or HRP/PrimaryPart.
local function getBarAnchor(model: Model)
	return model:FindFirstChild("Body")
		or model:FindFirstChild("Head")
		or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
end

local function ensureBar(enemy: Instance)
	if not enemy or not enemy.Parent then return end
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
