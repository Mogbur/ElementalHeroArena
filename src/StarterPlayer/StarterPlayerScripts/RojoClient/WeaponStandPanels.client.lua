-- WeaponStandPanels.client.lua

local Players = game:GetService("Players")
local PPS     = game:GetService("ProximityPromptService")
local RS      = game:GetService("ReplicatedStorage")
local Run     = game:GetService("RunService")
local LOCAL   = Players.LocalPlayer

-- Modules
local Modules      = RS:WaitForChild("Modules")
local WeaponStyles = require(Modules:WaitForChild("WeaponStyles"))
local StyleMastery = require(Modules:WaitForChild("StyleMastery"))

-- Positioning (left/right is fine; this keeps a small forward/camera nudge)
local RIGHT_OFFSET     = 0.5
local UP_OFFSET        = 3.0
local FWD_LOCAL_OFFSET = 5.0
local CAMERA_NUDGE     = 0.5

-- Template lookup (unchanged)
local function findTemplate(): BillboardGui?
	local ui = RS:FindFirstChild("UI")
	if ui then
		local t = ui:FindFirstChild("StandPanel")
		if t and t:IsA("BillboardGui") then return t end
	end
	local ws = workspace:FindFirstChild("StandPanel", true)
	if ws and ws:IsA("BillboardGui") then return ws end
	return nil
end
local Template = findTemplate()

-- Root detection
local function styleFromModel(model: Instance)
	if not model then return "SwordShield" end
	local n = string.lower(model.Name)
	if n:find("mace") then return "Mace" end
	if n:find("bow")  then return "Bow"  end
	return "SwordShield"
end

local function getRootFromPrompt(prompt: ProximityPrompt): (BasePart?, Model?)
	if not prompt then return nil, nil end
	local stand = prompt:FindFirstAncestorOfClass("Model")
	if not stand and prompt.Parent and prompt.Parent:IsA("Model") then stand = prompt.Parent end
	if stand then
		local sr = stand:FindFirstChild("StandRoot")
		if sr and sr:IsA("BasePart") then return sr, stand end
		if stand.PrimaryPart and stand.PrimaryPart:IsA("BasePart") then return stand.PrimaryPart, stand end
	end
	local p = prompt.Parent
	if p then
		if p:IsA("Attachment") and p.Parent and p.Parent:IsA("BasePart") then
			return p.Parent, p.Parent:FindFirstAncestorOfClass("Model")
		elseif p:IsA("BasePart") then
			return p, p:FindFirstAncestorOfClass("Model")
		end
	end
	return nil, nil
end

local function isWeaponStandPrompt(prompt: ProximityPrompt): (boolean, BasePart?, Model?)
	local root, stand = getRootFromPrompt(prompt)
	if not root or not stand then return false end
	local looksLikeStand = (string.lower(stand.Name or ""):find("stand") ~= nil)
	local tagged = (stand:GetAttribute("IsWeaponStand") == true)
	if looksLikeStand or tagged then return true, root, stand end
	return false
end

-- UI helpers
local function styleText(t: TextLabel, size: number, bold: boolean?, center: boolean?)
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.new(1,1,1)
	t.TextStrokeColor3 = Color3.new(0,0,0)
	t.TextStrokeTransparency = 0.1
	t.TextXAlignment = center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Font = bold and Enum.Font.GothamBlack or Enum.Font.Gotham
	t.TextScaled = false
	t.TextSize = size
end

local function ensureGraphite(card: Instance)
	if not (card and card:IsA("Frame")) then return end
	card.ClipsDescendants = true
	card.BackgroundColor3 = Color3.fromRGB(18,22,28)
	card.BackgroundTransparency = 0.25
	card.BorderSizePixel = 0
	if not card:FindFirstChild("CardStroke") then
		local s = Instance.new("UIStroke")
		s.Name="CardStroke"; s.Color=Color3.new(0,0,0); s.Thickness=2; s.Transparency=0.15; s.Parent=card
	end
	if not card:FindFirstChild("CardCorner") then
		local c = Instance.new("UICorner"); c.Name="CardCorner"; c.CornerRadius=UDim.new(0,12); c.Parent=card
	end
	if not card:FindFirstChild("CardPad") then
		local p=Instance.new("UIPadding"); p.Name="CardPad"
		p.PaddingTop=UDim.new(0,8); p.PaddingBottom=UDim.new(0,8); p.PaddingLeft=UDim.new(0,10); p.PaddingRight=UDim.new(0,10)
		p.Parent=card
	end
	if not card:FindFirstChild("CardGradient") then
		local g=Instance.new("UIGradient"); g.Name="CardGradient"; g.Rotation=90
		g.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(28,32,40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12,15,20)),
		}
		g.Parent=card
	end
end

-- Create panel
local panelsByRoot : {[BasePart]: BillboardGui} = {}
local connsByRoot  : {[BasePart]: RBXScriptConnection} = {}

local function makePanelFor(root: BasePart): BillboardGui
	if panelsByRoot[root] then return panelsByRoot[root] end
	local gui: BillboardGui
	if Template and Template:IsA("BillboardGui") then
		gui = Template:Clone()
	else
		gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(330, 280)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 70

		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Size = UDim2.fromScale(1,1)
		card.Parent = gui
		ensureGraphite(card)

		local function mk(name: string, y: number, h: number, size: number, bold: boolean?, center: boolean?)
			local t = Instance.new("TextLabel"); t.Name = name
			t.Position = UDim2.fromOffset(0,y); t.Size = UDim2.new(1,0,0,h)
			styleText(t, size, bold, center); t.Parent = card; return t
		end

		mk("Title",        6,  30, 26, true)  -- Title
		mk("Stat_Dmg",    40,  24, 22, true)  -- Damage
		mk("Stat_Spd",    66,  24, 22, true)  -- Speed
		mk("Stat_HP",     92,  24, 22, true)  -- Health (always shown)

		mk("MasteryHead",118,  22, 20, true, true).Text = "Mastery (Lvl.1)" -- will update

		mk("MasteryMain",142,  22, 20, true)   -- main line
		mk("MasteryNote",166,  22, 18, false)  -- note line

		local bar = Instance.new("Frame")
		bar.Name = "MasteryBar"
		bar.BackgroundColor3 = Color3.fromRGB(25,25,25)
		bar.BorderSizePixel  = 0
		bar.Position = UDim2.fromOffset(0, 192)
		bar.Size = UDim2.new(1, 0, 0, 20)
		bar.ZIndex = 2
		bar.Parent = card
		local bc = Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,8); bc.Parent=bar

		local fill = Instance.new("Frame")
		fill.Name = "Fill"; fill.BackgroundColor3 = Color3.fromRGB(74,197,90)
		fill.BorderSizePixel = 0; fill.Size = UDim2.fromScale(0,1); fill.ZIndex = 3; fill.Parent = bar
		local fc = Instance.new("UICorner"); fc.CornerRadius=UDim.new(0,8); fc.Parent=fill

		local txt = Instance.new("TextLabel")
		txt.Name="MasteryText"; txt.BackgroundTransparency=1; txt.Size=UDim2.fromScale(1,1); txt.ZIndex=4
		styleText(txt, 16, true, true); txt.Parent = bar
	end

	gui.Parent = root
	gui.Adornee = root
	gui.AlwaysOnTop = true
	panelsByRoot[root] = gui

	-- Place next to stand (+Right, +Up, +Forward, +tiny camera nudge)
	if connsByRoot[root] then connsByRoot[root]:Disconnect() end
	connsByRoot[root] = Run.RenderStepped:Connect(function()
		if not root or not root.Parent or not gui.Parent then return end
		local cf = root.CFrame
		local right, up, fwd = cf.RightVector, cf.UpVector, cf.LookVector
		local toCam = Vector3.new()
		local cam = workspace.CurrentCamera
		if cam and cam.CFrame then
			local v = (cam.CFrame.Position - root.Position)
			if v.Magnitude > 0.001 then toCam = v.Unit * CAMERA_NUDGE end
		end
		gui.StudsOffsetWorldSpace = right*RIGHT_OFFSET + up*UP_OFFSET + fwd*FWD_LOCAL_OFFSET + toCam
	end)

	local card = gui:FindFirstChild("Card", true)
	if card and card:IsA("Frame") then ensureGraphite(card) end
	return gui
end

-- Remote: just need XP (client now computes rank & progress)
local function getMasteryXP(styleName: string): number
	local remotes = RS:FindFirstChild("Remotes")
	local rf = remotes and remotes:FindFirstChild("GetWeaponMastery")
	if rf and rf:IsA("RemoteFunction") then
		local ok, ans = pcall(function() return rf:InvokeServer(styleName) end)
		if ok and type(ans)=="table" and type(ans.xp)=="number" then
			return ans.xp
		end
	end
	return 0
end

-- Update text
local function updatePanelText(gui: BillboardGui, styleName: string, stand: Instance?)
	local W = WeaponStyles[styleName] or {}
	local pretty = (styleName=="SwordShield") and "Sword & Shield" or styleName

	-- Base stats from WeaponStyles
	local atk = W.atkMul or 1.0
	local spd = W.spdMul or 1.0
	local hp  = W.hpMul  or 1.0

	-- Live mastery level/progress
	local xp = getMasteryXP(styleName)
	local lvl, into, span, isMax = StyleMastery.progress(xp)
	local rBon = StyleMastery.bonuses(styleName, xp) or {}

	-- Mastery lines per style
	local main, note
	if styleName == "Mace" then
		local chance = (rBon.stunChance or 0) * 100
		local dur    = (W.stunDur or 0.6)
		main = ("Stagger Chance %d%%"):format(math.floor(chance + 0.5))
		note = ("Stun %.1fs"):format(dur)
	elseif styleName == "Bow" then
		local nth    = W.forcedCritNth or 6
		local bonus  = math.floor(((W.forcedCritBonus or 0.40) * 100) + 0.5)
		local crit   = math.max(0, ((rBon.critDmgMul or 1.0) - 1.0) * 100)
		main = ("%dth hit: +%d%% dmg"):format(nth, bonus)
		note = ("Crit dmg bonus +%.1f%%"):format(crit)
	else -- Sword & Shield
		local drPct = math.floor(((W.guardDR or 0.50) * 100) + 0.5)
		local cd    = math.floor((W.guardCD or 6.0) + 0.5)
		local flat  = math.floor(((rBon.drFlat or 0) * 100) + 0.5)
		main = ("Block -%d%% dmg"):format(drPct)
		note = ("Every %ss | +%d%% Dmg.Reduced"):format(cd, flat)
	end

	-- Write UI
	local function set(path: string, txt: string)
		local inst = gui:FindFirstChild(path, true)
		if inst and inst:IsA("TextLabel") then inst.Text = txt end
	end

	set("Title", pretty)
	set("Stat_Dmg", ("Damage x%.2f"):format(atk))
	set("Stat_Spd", ("Speed  x%.2f"):format(spd))
	set("Stat_HP",  ("Health x%.2f"):format(hp)) -- always show

	set("MasteryHead", ("Mastery (Lvl.%d)"):format(lvl))
	set("MasteryMain", main)
	set("MasteryNote", note)

	-- Per-level bar fill + text
	local bar  = gui:FindFirstChild("MasteryBar", true) :: Frame
	local fill = bar and bar:FindFirstChild("Fill") :: Frame
	local mt   = bar and bar:FindFirstChild("MasteryText") :: TextLabel
	if bar and fill and mt then
		if isMax then
			fill.Size = UDim2.fromScale(1, 1)
			mt.Text = "MAX"
		else
			local ratio = (span > 0) and (into / span) or 0
			fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
			mt.Text = ("%d/%d"):format(math.floor(into + 0.5), math.floor(span + 0.5))
		end
	end
end

-- Show/Hide
local function onShown(prompt: ProximityPrompt)
	local ok, root, stand = isWeaponStandPrompt(prompt); if not ok then return end
	local gui = makePanelFor(root :: BasePart)
	updatePanelText(gui, styleFromModel(stand :: Model), stand)
	gui.Enabled = true
end

local function onHidden(prompt: ProximityPrompt)
	local ok, root = isWeaponStandPrompt(prompt); if not ok then return end
	local gui = panelsByRoot[root :: BasePart]; if gui then gui.Enabled = false end
end

print("[StandUI] boot")
PPS.PromptShown:Connect(onShown)
PPS.PromptHidden:Connect(onHidden)

-- Warm scan
task.defer(function()
	local char = LOCAL.Character or LOCAL.CharacterAdded:Wait()
	char:WaitForChild("HumanoidRootPart"); task.wait(0.25)
	for _, prompt in ipairs(workspace:GetDescendants()) do
		if prompt:IsA("ProximityPrompt") then
			local ok = isWeaponStandPrompt(prompt)
			if ok then onShown(prompt) end
		end
	end
end)

-- Cleanup
LOCAL.CharacterAdded:Connect(function()
	for _, c in pairs(connsByRoot) do c:Disconnect() end
	table.clear(connsByRoot)
	for _, gui in pairs(panelsByRoot) do if gui then gui:Destroy() end end
	table.clear(panelsByRoot)
end)
