-- HeroHUD.client.lua
-- World-space HP bar (with numbers) + thin shield bar (with numbers) for YOUR hero only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

-- === find your hero under your plot ===
local function findMyHero()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == LP.UserId then
			local hero = plot:FindFirstChild("Hero", true)
			if hero and hero:IsA("Model") then
				return hero, plot
			end
		end
	end
end

-- === build the billboard (HP + shield) ===
local function buildGui(hrp)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HeroHUD"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(140, 28) -- HP 18px + shield 10px
	bb.StudsOffset = Vector3.new(0, 3.1, 0)
	bb.Adornee = hrp

	-- root
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1,1)
	root.Parent = bb

	-- HP background
	local hpBG = Instance.new("Frame")
	hpBG.Name = "HPBG"
	hpBG.BackgroundColor3 = Color3.fromRGB(25,25,25)
	hpBG.BorderSizePixel = 0
	hpBG.Size = UDim2.fromOffset(bb.Size.X.Offset, 18)
	hpBG.Position = UDim2.fromOffset(0, 0)
	hpBG.Parent = root
	Instance.new("UICorner", hpBG).CornerRadius = UDim.new(0, 6)
	local hpBGStroke = Instance.new("UIStroke", hpBG)
	hpBGStroke.Thickness = 2
	hpBGStroke.Color = Color3.fromRGB(0,0,0)

	-- HP fill
	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.BackgroundColor3 = Color3.fromRGB(80, 235, 100)
	hpFill.BorderSizePixel = 0
	hpFill.Size = UDim2.fromScale(1,1)
	hpFill.Parent = hpBG
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 6)

	-- HP text
	local hpText = Instance.new("TextLabel")
	hpText.BackgroundTransparency = 1
	hpText.Size = UDim2.fromScale(1,1)
	hpText.Font = Enum.Font.GothamBold
	hpText.TextColor3 = Color3.new(1,1,1)
	hpText.TextScaled = true
	hpText.Parent = hpBG
	local hpStroke = Instance.new("UIStroke", hpText)
	hpStroke.Thickness = 2
	hpStroke.Color = Color3.fromRGB(0,0,0)
	hpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Outline

	-- Shield background (thinner, below HP)
	local shBG = Instance.new("Frame")
	shBG.Name = "ShieldBG"
	shBG.BackgroundColor3 = Color3.fromRGB(20,20,32)
	shBG.BorderSizePixel = 0
	shBG.Size = UDim2.fromOffset(bb.Size.X.Offset, 8)
	shBG.Position = UDim2.fromOffset(0, 18) -- just below HP bar
	shBG.Parent = root
	Instance.new("UICorner", shBG).CornerRadius = UDim.new(0, 4)

	-- Shield fill
	local shFill = Instance.new("Frame")
	shFill.Name = "ShieldFill"
	shFill.BackgroundColor3 = Color3.fromRGB(95,170,255)
	shFill.BorderSizePixel = 0
	shFill.Size = UDim2.fromScale(0,1)
	shFill.Parent = shBG
	Instance.new("UICorner", shFill).CornerRadius = UDim.new(0, 4)

	-- Shield text (numbers inside)
	local shText = Instance.new("TextLabel")
	shText.BackgroundTransparency = 1
	shText.Size = UDim2.fromScale(1,1)
	shText.Font = Enum.Font.GothamBold
	shText.TextColor3 = Color3.fromRGB(220,235,255)
	shText.TextScaled = true
	shText.Parent = shBG
	local shStroke = Instance.new("UIStroke", shText)
	shStroke.Thickness = 2
	shStroke.Color = Color3.fromRGB(0,0,0)
	shStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Outline

	return bb, hpFill, hpText, shBG, shFill, shText
end

-- === attach + live update ===
local currentHero
local maid = {}

local function cleanup()
	for _, conn in ipairs(maid) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(maid)
	if currentHero then
		local gui = currentHero:FindFirstChild("HeroHUD")
		if gui then gui:Destroy() end
	end
	currentHero = nil
end

local function attach(hero)
	cleanup()
	currentHero = hero

	local hum = hero:FindFirstChildOfClass("Humanoid")
	local hrp = hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
	if not (hum and hrp) then return end

	local bb, hpFill, hpText, shBG, shFill, shText = buildGui(hrp)
	bb.Parent = hero

	-- show/hide with BarsVisible attribute (server drives this in PlotService)
	local function setBars(on)
		bb.Enabled = (on == 1 or on == true)
	end
	setBars(hero:GetAttribute("BarsVisible"))
	table.insert(maid, hero:GetAttributeChangedSignal("BarsVisible"):Connect(function()
		setBars(hero:GetAttribute("BarsVisible"))
	end))

	local function refresh()
		if not (hum and hum.Parent) then return end

		-- HP
		local hp = math.max(0, math.floor(hum.Health + 0.5))
		local max = math.max(1, math.floor(hum.MaxHealth + 0.5))
		local frac = math.clamp(hp / max, 0, 1)
		hpFill.Size = UDim2.new(frac, 0, 1, 0)
		hpText.Text = string.format("%d / %d", hp, max)

		-- Shield (reads Combat/Forge attributes)
		local s = math.max(0, math.floor(tonumber(hero:GetAttribute("ShieldHP")) or 0))
		local sMaxAttr = math.max(0, math.floor(tonumber(hero:GetAttribute("ShieldMax")) or 0))
		local sMax = math.max(sMaxAttr, s) -- if ShieldMax is missing (Aquabarrier), treat current as cap

		-- handle time-based expiry
		local exp = tonumber(hero:GetAttribute("ShieldExpireAt")) or 0
		if exp > 0 and os.clock() >= exp then s = 0 end

		if sMax <= 0 or s <= 0 then
			shBG.Visible = false
		else
			shBG.Visible = true
			local sFrac = math.clamp(s / sMax, 0, 1)
			shFill.Size = UDim2.new(sFrac, 0, 1, 0)
			shText.Text = tostring(s)
		end
	end

	-- health + shield change hooks
	table.insert(maid, hum.HealthChanged:Connect(refresh))
	table.insert(maid, hum:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
	table.insert(maid, hero:GetAttributeChangedSignal("ShieldHP"):Connect(refresh))
	table.insert(maid, hero:GetAttributeChangedSignal("ShieldMax"):Connect(refresh))
	table.insert(maid, hero:GetAttributeChangedSignal("ShieldExpireAt"):Connect(refresh))

	-- keep Adornee updated if HRP switches
	table.insert(maid, hero.ChildAdded:Connect(function(c)
		if c.Name == "HumanoidRootPart" and c:IsA("BasePart") then bb.Adornee = c end
	end))

	refresh()
end

-- === watcher loop: (re)attach whenever your hero instance changes ===
task.spawn(function()
	while true do
		local hero = select(1, findMyHero())
		if hero and hero ~= currentHero then
			attach(hero)
		elseif not hero and currentHero then
			cleanup()
		end
		task.wait(0.25)
	end
end)
