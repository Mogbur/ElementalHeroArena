-- StarterPlayerScripts/SkillBoardUI.client.lua
-- World-board skill picker + info + hold-to-upgrade + button SFX.

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local Tween      = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local lp         = Players.LocalPlayer

-- ---------- remotes ----------
local Remotes  = RS:WaitForChild("Remotes")
local RE_Equip = Remotes:WaitForChild("SkillEquipRequest")
local RE_Buy   = Remotes:WaitForChild("SkillPurchaseRequest")

-- ---------- skill data ----------
local SkillConfig = require(RS.Modules.SkillConfig)
local SkillTuning = require(RS.Modules.SkillTuning)

local function nextCost(skillId, curLv)
    local nextLv = math.clamp((curLv or 0) + 1, 1, (SkillTuning.MAX_LEVEL or 5))
    local c = (SkillTuning.Costs and SkillTuning.Costs[skillId] and SkillTuning.Costs[skillId][nextLv]) or {}
    local flux = tonumber(c.flux) or 0
    local ess  = c.essence or c.ess or {}
    return flux, ess, nextLv
end

local SKILLS = { "firebolt","aquabarrier","quakepulse" }

local META = {
	firebolt    = { name="Firebolt",    elem="Fire",  icon="rbxassetid://6480613420" },
	aquabarrier = { name="AquaBarrier", elem="Water", icon="rbxassetid://14748565847"     },
	quakepulse  = { name="QuakePulse",  elem="Earth", icon="rbxassetid://117894152743510"  },
}

-- Lv5 perk blurbs
local PERK = {
	firebolt    = { locked = "Lv5 perk → Ignite (burn over time)",  unlocked = "Perk: Ignite — targets burn briefly" },
	aquabarrier = { locked = "Lv5 perk → Tidal Care (HoT + splash)", unlocked = "Perk: Tidal Care — (HoT + splash)" },
	quakepulse  = { locked = "Lv5 perk → Aftershock (second ring)",  unlocked = "Perk: Aftershock — second ring shortly after" },
}


local ELEM_COLOR = {
	Fire  = Color3.fromRGB(255,140, 80),
	Water = Color3.fromRGB( 90,180,255),
	Earth = Color3.fromRGB(200,175,120),
}
-- Put this right under ELEM_COLOR
local ELEM_ICON = {
	Fire  = "rbxassetid://91949104597643",
	Water = "rbxassetid://107473921254840",
	Earth = "rbxassetid://89574210557730",
}
local MAX_LEVEL = 5

-- small color helpers (kept if you want to reuse later)
local function brighten(c, a)
	return Color3.new(c.R + (1 - c.R) * a, c.G + (1 - c.G) * a, c.B + (1 - c.B) * a)
end
local function dim(c, a)
	return Color3.new(c.R * (1 - a), c.G * (1 - a), c.B * (1 - a))
end

-- tiny edge particles on the left/right edges of the 3D board part
local function setupEdgeParticles(textPart)
	local sizeX = (textPart.Size and textPart.Size.X) or 6
	local function mkSide(name, sign)
		local att = textPart:FindFirstChild(name)
		if not att then
			att = Instance.new("Attachment")
			att.Name = name
			att.Position = Vector3.new(sign * (sizeX * 0.5 - 0.05), 0, 0)
			att.Parent = textPart
		end
		local pe = att:FindFirstChildOfClass("ParticleEmitter")
		if not pe then
			pe = Instance.new("ParticleEmitter")
			pe.Parent = att
			pe.Enabled = false
			pe.Rate = 0
			pe.Lifetime = NumberRange.new(0.8, 1.4)
			pe.Speed = NumberRange.new(0.4, 1.2)
			pe.SpreadAngle = Vector2.new(12, 12)
			pe.Size = NumberSequence.new{
				NumberSequenceKeypoint.new(0.0, 0.26),
				NumberSequenceKeypoint.new(1.0, 0.12)
			}
			pe.Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.0, 0.15),
				NumberSequenceKeypoint.new(1.0, 1.0)
			}
			pe.LightEmission = 0.6
		end
		return pe
	end

	local left  = mkSide("FX_Left",  -1)
	local right = mkSide("FX_Right", 1)

	local function apply(elem)
		if elem == "Fire" then
			local c1, c2 = Color3.fromRGB(255,170, 80), Color3.fromRGB(255,110,40)
			local col = ColorSequence.new(c1, c2)
			left.Color,  right.Color  = col, col
			left.Rate,   right.Rate   = 4, 4
			left.Speed,  right.Speed  = NumberRange.new(0.8, 1.6), NumberRange.new(0.8, 1.6)
		elseif elem == "Water" then
			local c1, c2 = Color3.fromRGB(140,200,255), Color3.fromRGB(80,160,255)
			local col = ColorSequence.new(c1, c2)
			left.Color,  right.Color  = col, col
			left.Rate,   right.Rate   = 3, 3
			left.Speed,  right.Speed  = NumberRange.new(0.4, 1.0), NumberRange.new(0.4, 1.0)
		elseif elem == "Earth" then
			local c1, c2 = Color3.fromRGB(170,220,140), Color3.fromRGB(120,180,100)
			local col = ColorSequence.new(c1, c2)
			left.Color,  right.Color  = col, col
			left.Rate,   right.Rate   = 2, 2
			left.Speed,  right.Speed  = NumberRange.new(0.2, 0.8), NumberRange.new(0.2, 0.8)
		else
			left.Rate, right.Rate = 0, 0
		end
	end

	local function enable(on)
		left.Enabled, right.Enabled = on, on
	end

	return { apply = apply, enable = enable }
end

-- tolerant stats reader + fallback formulas
local function readStats(id, lv)
	lv = math.clamp(lv or 1, 1, MAX_LEVEL)

	-- use the SkillConfig you already required at the top
	local s = nil
	if SkillConfig and SkillConfig[id] and type(SkillConfig[id].stats) == "function" then
		s = SkillConfig[id].stats(lv)
	end
	s = s or {}

	-- Copy known fields AND pass-through shield (which we show on AquaBarrier)
	local out = {
		damage   = s.damage   or s.dmg or s.Damage,
		range    = s.range    or s.Range,
		cooldown = s.cooldown or s.cd or s.CD or s.Cooldown,
		duration = s.duration or s.Duration,
		radius   = s.radius   or s.Radius,
	}
	if s.shield ~= nil then out.shield = s.shield end

	-- Fallbacks so the board never looks empty (only used if SkillConfig gave nothing)
	if id == "firebolt" then
		out.damage   = out.damage   or (14 + 6*lv)
		out.range    = out.range    or 38
		out.cooldown = out.cooldown or 6
	elseif id == "aquabarrier" then
		out.duration = out.duration or 4
		out.cooldown = out.cooldown or 12
	elseif id == "quakepulse" then
		out.damage   = out.damage   or (10 + 5*lv)
		out.radius   = out.radius   or 22
		out.cooldown = out.cooldown or 8
	end

	return out
end

-- ---------- utility: plot + parts ----------
local function myPlot()
	local plots = workspace:FindFirstChild("Plots"); if not plots then return end
	for _,m in ipairs(plots:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == lp.UserId then return m end
	end
end
local function boardParts(plot)
	if not plot then return end
	local struct = plot:FindFirstChild("HeroPlotStructures", true)
	local board  = struct and struct:FindFirstChild("SkillBoard")
	if not board then return end
	return board, board:FindFirstChild("SkillBoardText"), board:FindFirstChild("SkillBoardPic")
end

-- ---------- attributes ----------
local function levelAttr(id) return "Skill_"..id end
local function getLevel(id)  return tonumber(lp:GetAttribute(levelAttr(id))) or 0 end
local selectedId = lp:GetAttribute("Equip_Primary") or "firebolt"
lp:GetAttributeChangedSignal("Equip_Primary"):Connect(function()
	selectedId = lp:GetAttribute("Equip_Primary") or selectedId
end)
local function setSelected(id) RE_Equip:FireServer({primary=id}) end

-- ==== multi-slot state (slot1 active, 2/3 locked for now) ====
local SLOT_COUNT = 3
local slotSkills = { [1] = selectedId, [2] = "firebolt", [3] = "firebolt" } -- icons for 2/3 are placeholders
local slotLocked = { [1] = false, [2] = true, [3] = true }

-- keep slot1 in sync when server confirms equip
lp:GetAttributeChangedSignal("Equip_Primary"):Connect(function()
	selectedId = lp:GetAttribute("Equip_Primary") or selectedId
	slotSkills[1] = selectedId
end)

-- small bridge so pic GUI can force-update the text GUI immediately
local forceTextRefresh = function() end

-- ---------- 3D SFX ----------
local function normalizeId(id)
	if not id then return nil end
	if typeof(id) == "number" then id = tostring(id) end
	if not string.find(id, "rbxassetid://", 1, true) then id = "rbxassetid://"..id end
	return id
end
local SFX = {
	click    = "rbxassetid://93927627634818",
	deny     = "rbxassetid://15921059398",
	upgrade  = "rbxassetid://8573766100",
}
local function play3D(id, pos, vol, minD, maxD)
	id = normalizeId(id); if not (id and pos) then return end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.Transparency = true, false, 1
	p.Size = Vector3.new(0.2,0.2,0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.7
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = minD or 10
	s.RollOffMaxDistance = maxD or 140
	s.EmitterSize = 10
	s.Parent = p
	s:Play()
	-- Use Connect (not :Once), then Debris cleans up the part anyway.
	s.Ended:Connect(function() if p then p:Destroy() end end)
	game:GetService("Debris"):AddItem(p, 8)
end

-- ---------- GUIs (pic + text) ----------
local textGui, picGui, lockedOverlay

local function buildPicGui(picPart)
	if picGui then picGui:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 45
	gui.Face = Enum.NormalId.Left
	gui.LightInfluence = 0
	gui.Adornee = picPart
	gui.Parent = picPart
	picGui = gui

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1,1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	-- --- slots bar across the base board ---
	local bar = Instance.new("Frame")
	bar.Name = "SlotsBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.07)
	bar.Size = UDim2.fromScale(0.96, 0.86)
	bar.BackgroundTransparency = 1
	bar.Parent = root

	-- utility
	local function skillIcon(id)
		local m = META[id] or META.firebolt
		return m.icon
	end
	local function cycleSkill(current, delta)
		local idx = table.find(SKILLS, current) or 1
		idx = ((idx - 1 + delta) % #SKILLS) + 1
		return SKILLS[idx]
	end

	-- build three slots (even margins + equal gaps)
	local MARGIN = 0.04   -- left/right margin inside the bar
	local GAP    = 0.02   -- gap between slots
	local slotW  = (1 - MARGIN*2 - GAP*(SLOT_COUNT - 1)) / SLOT_COUNT

	for i = 1, SLOT_COUNT do
		local slot = Instance.new("Frame")
		slot.Name = ("Slot%d"):format(i)
		slot.AnchorPoint = Vector2.new(0.5, 0.5)

		-- center of slot i
		local centerX = MARGIN + (i-1)*(slotW + GAP) + slotW/2
		slot.Position = UDim2.fromScale(centerX, 0.55)
		slot.Size     = UDim2.fromScale(slotW, 0.78)
		slot.BackgroundColor3 = Color3.fromRGB(25,25,25)
		slot.BackgroundTransparency = 1
		slot.Parent = bar

		-- icon
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.86, 0.86)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = skillIcon(slotSkills[i])
		icon.Parent = slot

		-- lock overlay (keep small "coming soon" only)
		local lock = Instance.new("TextLabel")
		lock.Name = "Lock"
		lock.AnchorPoint = Vector2.new(0.5, 0.5)
		lock.Position = UDim2.fromScale(0.5, 0.5)
		lock.Size = UDim2.fromScale(1, 1)
		lock.BackgroundColor3 = Color3.new(0,0,0)
		lock.BackgroundTransparency = 0.35
		lock.Text = "🔒  Locked"   -- <- remove the big "coming soon" text here
		lock.TextScaled = true
		lock.Font = Enum.Font.GothamBold
		lock.TextColor3 = Color3.new(1,1,1)
		lock.Visible = slotLocked[i] or false
		lock.Parent = slot

		-- small "coming soon" sticker near the bottom (only when locked)
		local soon = Instance.new("TextLabel")
		soon.Name = "Soon"
		soon.AnchorPoint = Vector2.new(0.5, 1)
		soon.Position = UDim2.fromScale(0.5, 0.96)
		soon.Size = UDim2.fromScale(0.98, 0.22)
		soon.BackgroundTransparency = 1
		soon.Text = "coming soon"
		soon.Font = Enum.Font.Gotham
		soon.TextScaled = false              -- keep it small, no wrapping
		soon.TextSize = 14
		soon.TextColor3 = Color3.fromRGB(255,235,190)
		soon.TextStrokeTransparency = 0.4
		soon.ZIndex = (lock.ZIndex or 1) + 1
		soon.Visible = lock.Visible
		soon.Parent = slot

		-- hide the icon when slot is locked, so the plank shows
		icon.Visible = not (slotLocked[i] or false)
		lock:GetPropertyChangedSignal("Visible"):Connect(function()
			icon.Visible = not lock.Visible
		end)



		-- keep slot #1 icon synced to server equip changes
		if i == 1 then
			lp:GetAttributeChangedSignal("Equip_Primary"):Connect(function()
				local newId = lp:GetAttribute("Equip_Primary") or slotSkills[1]
				slotSkills[1] = newId
				icon.Image = skillIcon(newId)
			end)
		end

		-- up/down arrows
		local function makeArrow(y, rot)
			local b = Instance.new("ImageButton")
			b.Name = y < 0.5 and "Up" or "Down"
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.fromScale(0.90, y)
			b.Size = UDim2.fromScale(0.18, 0.24)
			b.BackgroundTransparency = 1
			b.AutoButtonColor = true
			b.Image = "rbxassetid://7072718365"
			b.Rotation = rot
			b.Parent = slot
			return b
		end
		local upBtn   = makeArrow(0.18,   0)
		local downBtn = makeArrow(0.82, 180)

		local function tryBump(delta)
			if slotLocked[i] then
				play3D(SFX.deny, picPart.Position); return
			end
			-- only SLOT 1 actually equips + updates the text panel
			slotSkills[i] = cycleSkill(slotSkills[i], delta)
			icon.Image = skillIcon(slotSkills[i])

			if i == 1 then
				selectedId = slotSkills[1]
				setSelected(selectedId)         -- server reflect
				forceTextRefresh()              -- instant local reflect
				play3D(SFX.click, picPart.Position, 0.8)
			else
				play3D(SFX.deny, picPart.Position)
			end
		end

		upBtn.MouseButton1Click:Connect(function() tryBump(1)  end)
		downBtn.MouseButton1Click:Connect(function() tryBump(-1) end)

		-- subtle slot index tag
		local tag = Instance.new("TextLabel")
		tag.AnchorPoint = Vector2.new(0, 0)
		tag.Position = UDim2.fromScale(0.04, 0.02)
		tag.Size = UDim2.fromScale(0.26, 0.20)
		tag.BackgroundTransparency = 1
		tag.Text = ("#%d"):format(i)
		tag.Font = Enum.Font.GothamBold
		tag.TextScaled = true
		tag.TextColor3 = i == 1 and Color3.fromRGB(255,255,255) or Color3.fromRGB(200,200,200)
		tag.Parent = slot
	end
end

local function row(parent, y, iconId, label)
	local r = Instance.new("Frame")
	r.Size = UDim2.fromScale(1,0.16)
	r.Position = UDim2.fromScale(0,y)
	r.BackgroundTransparency = 1
	r.Parent = parent
	local ic = Instance.new("ImageLabel")
	ic.BackgroundTransparency = 1
	ic.Size = UDim2.fromScale(0.16,1)
	ic.Image = iconId
	ic.Parent = r
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(0.34,1)
	lbl.Position = UDim2.fromScale(0.16,0)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(235,235,235)
	lbl.Text = label
	lbl.Parent = r
	local val = Instance.new("TextLabel")
	val.BackgroundTransparency = 1
	val.Size = UDim2.fromScale(0.50,1)
	val.Position = UDim2.fromScale(0.50,0)
	val.Font = Enum.Font.GothamBlack
	val.TextScaled = true
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.TextColor3 = Color3.fromRGB(255,255,255)
	val.Text = "--"
	val.Parent = r
	return {frame=r,value=val,label=lbl}
end

local function buildTextGui(textPart)
	if textGui then textGui:Destroy() end
	local gui = Instance.new("SurfaceGui")
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 45
	gui.Face = Enum.NormalId.Left
	gui.LightInfluence = 0
	gui.Adornee = textPart
	gui.Parent = textPart
	textGui = gui

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1,1)
	root.BackgroundColor3 = Color3.fromRGB(40,40,50)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local pad = Instance.new("UIPadding", root)
	pad.PaddingTop    = UDim.new(0,8)
	pad.PaddingBottom = UDim.new(0,8)
	pad.PaddingLeft   = UDim.new(0,12)
	pad.PaddingRight  = UDim.new(0,12)

	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1,0.20)
	header.BackgroundTransparency = 1
	header.Parent = root

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromScale(0.70,1)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextColor3 = Color3.new(1,1,1)
	nameLbl.Text = "Skill"
	nameLbl.Parent = header

	local lvlLbl = Instance.new("TextLabel")
	lvlLbl.Size = UDim2.fromScale(0.30,1)
	lvlLbl.Position = UDim2.fromScale(0.70,0)
	lvlLbl.BackgroundTransparency = 1
	lvlLbl.Font = Enum.Font.GothamBold
	lvlLbl.TextScaled = true
	lvlLbl.TextXAlignment = Enum.TextXAlignment.Right
	lvlLbl.TextColor3 = Color3.new(1,1,1)
	lvlLbl.Text = ("Lv %d / %d"):format(1, MAX_LEVEL)
	lvlLbl.Parent = header

	-- === Element badge (emoji in colored pill BEFORE the name) ===
	local badge = Instance.new("Frame")
	badge.Name = "ElemBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.fromScale(0.00, 0.50)   -- left edge of the header
	badge.Size = UDim2.fromScale(0.10, 0.70)       -- small pill
	badge.BackgroundColor3 = Color3.fromRGB(120,120,120)
	badge.BackgroundTransparency = 0.15
	badge.Parent = header

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0.5, 0)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Thickness = 2
	badgeStroke.Transparency = 0.25
	badgeStroke.Parent = badge

	-- icon inside the pill
	local badgeIcon = Instance.new("ImageLabel")
	badgeIcon.Name = "Icon"
	badgeIcon.BackgroundTransparency = 1
	badgeIcon.AnchorPoint = Vector2.new(0.5,0.5)
	badgeIcon.Position = UDim2.fromScale(0.5,0.5)
	badgeIcon.Size = UDim2.fromScale(0.78, 0.78)   -- tight inside the pill
	badgeIcon.ScaleType = Enum.ScaleType.Fit
	badgeIcon.Image = ""
	badgeIcon.Parent = badge

	-- very soft element gradient in the pill (so it’s not the same “flat” look as the tray)
	local badgeGrad = Instance.new("UIGradient")
	badgeGrad.Rotation = 90
	badgeGrad.Parent = badge

	-- slow, subtle rotation to keep it alive
	task.spawn(function()
		while badge and badge.Parent do
			local t = Tween:Create(badgeGrad, TweenInfo.new(6, Enum.EasingStyle.Linear), {Rotation = badgeGrad.Rotation + 180})
			t:Play(); t.Completed:Wait()
		end
	end)

	-- shift the name to the right so it never overlaps the badge
	nameLbl.Position = UDim2.fromScale(0.12, 0)
	nameLbl.Size     = UDim2.fromScale(0.58, 1)

	-- tiny helper for emoji
	local function elemEmoji(elem)
		if elem == "Fire" then return "🔥"
		elseif elem == "Water" then return "💧"
		elseif elem == "Earth" then return "🌿" end
		return "✨"
	end

	-- === Element border (animated stroke) ===
	local border = Instance.new("Frame")
	border.Name = "ElementBorder"
	border.BackgroundTransparency = 1
	border.Size = UDim2.fromScale(1,1)
	border.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 6
	stroke.Transparency = 0.28
	stroke.Color = Color3.fromRGB(150,150,150)
	stroke.Parent = border

	-- gentle pulse forever
	task.spawn(function()
		while border.Parent do
			local t1 = Tween:Create(stroke, TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Thickness = 8, Transparency = 0.16
			})
			t1:Play(); t1.Completed:Wait()
			local t2 = Tween:Create(stroke, TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Thickness = 5, Transparency = 0.32
			})
			t2:Play(); t2.Completed:Wait()
		end
	end)

	-- === Tiny edge particles on the board part itself ===
	local fx = setupEdgeParticles(textPart)

	-- proximity gating (cheap): only show FX when you're near your board
	task.spawn(function()
		while root.Parent do
			local char = lp.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			local on = false
			if hrp and textPart then
				on = (hrp.Position - textPart.Position).Magnitude < 22
			end
			fx.enable(on)
			task.wait(0.25)
		end
	end)

	-- divider stripe
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.fromScale(1, 0.03)
	stripe.Position = UDim2.fromScale(0, 0.20)
	stripe.BackgroundColor3 = Color3.fromRGB(120,120,120)
	stripe.BorderSizePixel = 0
	stripe.Parent = root

	-- stats block (original placement)
	local stats = Instance.new("Frame")
	stats.Size = UDim2.fromScale(1, 0.55)
	stats.Position = UDim2.fromScale(0, 0.23)
	stats.BackgroundTransparency = 1
	stats.Parent = root


	local rows = {
		Damage   = row(stats, 0.00, "rbxassetid://6031057797", "Damage"),
		Range    = row(stats, 0.19, "rbxassetid://6031229373", "Range"),
		Cooldown = row(stats, 0.38, "rbxassetid://6031068421", "Cooldown"),
		Extra    = row(stats, 0.57, "rbxassetid://6031075931", ""),
	}
	rows.Extra.frame.Visible = false

	-- perk line (sits above the green upgrade bar)
	local perkLbl = Instance.new("TextLabel")
	perkLbl.BackgroundTransparency = 1
	perkLbl.Size = UDim2.fromScale(1, 0.08)
	perkLbl.Position = UDim2.fromScale(0, 0.71)
	perkLbl.Font = Enum.Font.GothamBold
	perkLbl.TextScaled = true
	perkLbl.TextXAlignment = Enum.TextXAlignment.Left
	perkLbl.TextColor3 = Color3.fromRGB(235,235,235)
	perkLbl.Text = ""
	perkLbl.Parent = root

	-- === UPGRADE BUTTON + FILL (create first) ===
	local upgrade = Instance.new("TextButton")
	upgrade.Size = UDim2.fromScale(1,0.19)
	upgrade.Position = UDim2.fromScale(0,0.81)
	upgrade.BackgroundColor3 = Color3.fromRGB(60,140,60)
	upgrade.Text = ""  -- label lives in upText now
	upgrade.AutoButtonColor = false
	upgrade.Font = Enum.Font.GothamBlack
	upgrade.TextScaled = true
	upgrade.TextColor3 = Color3.new(1,1,1)
	upgrade.Parent = root
	Instance.new("UICorner", upgrade).CornerRadius = UDim.new(0,12)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0,1)
	fill.BackgroundColor3 = Color3.fromRGB(80,200,80)
	fill.BackgroundTransparency = 0.15
	fill.Parent = upgrade
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0,12)

		-- === INLINE COSTS inside the button (left), then the label ===
	local costInline = Instance.new("Frame")
	costInline.Name = "CostInline"
	costInline.BackgroundTransparency = 1
	costInline.AnchorPoint = Vector2.new(0, 0.5)
	costInline.Position = UDim2.fromScale(0, 0.5)
	costInline.Size = UDim2.fromOffset(0, 26)         -- fixed height; width auto
	costInline.AutomaticSize = Enum.AutomaticSize.X
	costInline.Parent = upgrade

	local listIn = Instance.new("UIListLayout", costInline)
	listIn.FillDirection = Enum.FillDirection.Horizontal
	listIn.Padding = UDim.new(0, 6)
	listIn.VerticalAlignment = Enum.VerticalAlignment.Center

	local function mkMini(imgId)
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(0, 26)
		f.AutomaticSize = Enum.AutomaticSize.X
		f.Parent = costInline

		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Size = UDim2.fromOffset(24,24)
		ic.AnchorPoint = Vector2.new(0,0.5)
		ic.Position = UDim2.new(0,0,0.5,0)
		ic.Image = imgId
		ic.Parent = f

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.TextColor3 = Color3.new(1,1,1)
		lbl.Text = "x0"
		lbl.Position = UDim2.new(0, 26, 0, 0)
		lbl.Size = UDim2.fromOffset(34,24)
		lbl.Parent = f
		return f, lbl
	end

	-- same icons you used in ResourceTray
	local iconFlux  = "rbxassetid://13219079846"
	local iconFire  = "rbxassetid://86006404657315"
	local iconWater = "rbxassetid://83220825471966"
	local iconEarth = "rbxassetid://100036266210611"

	local fluxChip,  fluxLbl  = mkMini(iconFlux)
	local fireChip,  fireLbl  = mkMini(iconFire)
	local waterChip, waterLbl = mkMini(iconWater)
	local earthChip, earthLbl = mkMini(iconEarth)

	-- actual text lives after the chips
	local upText = Instance.new("TextLabel")
	upText.Name = "UpgradeText"
	upText.BackgroundTransparency = 1
	upText.TextScaled = true
	upText.Font = Enum.Font.GothamBlack
	upText.TextColor3 = Color3.new(1,1,1)
	upText.TextXAlignment = Enum.TextXAlignment.Left
	upText.AnchorPoint = Vector2.new(0,0.5)
	upText.Position = UDim2.fromScale(0,0.5) -- adjusted in placeUpgradeText()
	upText.Size     = UDim2.fromScale(1,1)
	upText.Parent = upgrade

	local function placeUpgradeText()
		local used = listIn.AbsoluteContentSize.X
		upText.Position = UDim2.new(0, used + 12, 0.5, 0)
		upText.Size     = UDim2.new(1, -(used + 16), 1, 0)
	end
	listIn:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(placeUpgradeText)
	task.defer(placeUpgradeText)

	-- refresher for those inline costs
	local function refreshCostInline(skillId)
		local lv = tonumber(lp:GetAttribute("Skill_"..skillId)) or 0
		local flux, ess = nextCost(skillId, lv)

		fluxChip.Visible = flux > 0; if flux > 0 then fluxLbl.Text = "x"..flux end

		local f = tonumber(ess.Fire or 0)
		local w = tonumber(ess.Water or 0)
		local e = tonumber(ess.Earth or 0)

		fireChip.Visible  = f > 0; if f > 0 then fireLbl.Text  = "x"..f end
		waterChip.Visible = w > 0; if w > 0 then waterLbl.Text = "x"..w end
		earthChip.Visible = e > 0; if e > 0 then earthLbl.Text = "x"..e end

		task.defer(placeUpgradeText)
	end

	-- locked overlay
	lockedOverlay = Instance.new("TextLabel")
	lockedOverlay.Size = UDim2.fromScale(1,1)
	lockedOverlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
	lockedOverlay.BackgroundTransparency = 0.35
	lockedOverlay.Text = "Locked during combat"
	lockedOverlay.TextColor3 = Color3.new(1,1,1)
	lockedOverlay.Font = Enum.Font.GothamBlack
	lockedOverlay.TextScaled = true
	lockedOverlay.Visible = false
	lockedOverlay.Parent = root

	-- keep the big overlay in sync with plot state
	local function syncCombatLockOverlay()
		local plot = myPlot()
		if not plot then
			lockedOverlay.Visible = true
			lockedOverlay.Text = "Locked"
			return
		end
		-- server meaning: CombatLocked == false -> waves running
		local fighting = (plot:GetAttribute("CombatLocked") == false)
		local atIdle   = (plot:GetAttribute("AtIdle") == true)
		-- show overlay while fighting or before we've parked at the idle pad
		lockedOverlay.Visible = fighting or (not atIdle)
	end

	-- updater
	local function fmtDelta(v, nv)
		return (nv and nv ~= v) and ("%s  ►  %s"):format(v, nv) or tostring(v)
	end

	local function update()
		local meta = META[selectedId] or META.firebolt
		local elem = meta.elem
		local lv   = getLevel(selectedId)
		local cur  = readStats(selectedId, math.max(lv,1))
		local nxt  = (lv < MAX_LEVEL) and readStats(selectedId, lv+1) or nil
		refreshCostInline(selectedId)

		nameLbl.Text = meta.name
		lvlLbl.Text  = ("Lv %d / %d"):format(lv, MAX_LEVEL)

		-- element color -> stripe, border, badge, and particles
		local base = ELEM_COLOR[elem] or Color3.fromRGB(150,150,150)
		stroke.Color = base
		fx.apply(elem)
		badge.BackgroundColor3 = base
		badgeStroke.Color = base
		-- new: icon + gradient
		badgeIcon.Image = ELEM_ICON[elem] or ""
		if badge:FindFirstChildOfClass("UIGradient") then
			local g = badge:FindFirstChildOfClass("UIGradient")
			g.Color = ColorSequence.new(
				brighten(base, 0.28),
				dim(base, 0.10)
			)
		end

		stripe.BackgroundColor3 = base

		-- base visibility + default labels
		rows.Damage.frame.Visible   = cur.damage   ~= nil
		rows.Range.frame.Visible    = cur.range    ~= nil
		rows.Cooldown.frame.Visible = cur.cooldown ~= nil

		rows.Damage.label.Text   = "Damage"
		rows.Range.label.Text    = "Range"
		rows.Cooldown.label.Text = "Cooldown"

		if cur.damage   ~= nil then rows.Damage.value.Text   = fmtDelta(cur.damage,   nxt and nxt.damage) end
		if cur.range    ~= nil then rows.Range.value.Text    = fmtDelta(cur.range,    nxt and nxt.range) end
		if cur.cooldown ~= nil then rows.Cooldown.value.Text = fmtDelta(cur.cooldown, nxt and nxt.cooldown) end

		-- optional extra row depending on skill
		rows.Extra.frame.Visible = false

		if selectedId == "aquabarrier" then
			-- DoT (5s) + Shield
			rows.Damage.label.Text = "DoT (5s)"
			rows.Range.frame.Visible = true
			rows.Range.label.Text    = "Shield"
			rows.Range.value.Text    = fmtDelta(cur.shield or 0, nxt and nxt.shield)

			rows.Extra.frame.Visible = true
			rows.Extra.label.Text    = "Duration"
			rows.Extra.value.Text    = fmtDelta(cur.duration or 0, nxt and nxt.duration)

		elseif selectedId == "quakepulse" then
			rows.Damage.label.Text = "Damage (AoE)"
			rows.Extra.frame.Visible = true
			rows.Extra.label.Text    = "Fracture"
			rows.Extra.value.Text    = "+15% dmg — 4s"
		end

		-- Lv5 perk line
		local perk = PERK[selectedId]
		if perk then
			if lv >= MAX_LEVEL then
				perkLbl.Text = perk.unlocked
				perkLbl.TextColor3 = Color3.fromRGB(255,255,255)
			else
				perkLbl.Text = perk.locked
				perkLbl.TextColor3 = Color3.fromRGB(220,220,220)
			end
			perkLbl.Visible = true
		else
			perkLbl.Visible = false
		end

		-- combat lock + button state
		local plot = myPlot()
		syncCombatLockOverlay()
		if lv >= MAX_LEVEL then
			upText.Text = "Max level"
			upgrade.BackgroundColor3 = Color3.fromRGB(90,90,90)
		else
			upText.Text = ("Hold to level up  →  %d"):format(lv+1)
			upgrade.BackgroundColor3 = Color3.fromRGB(60,140,60)
		end
	end

	-- expose updater to the Pic GUI and do an initial paint
	forceTextRefresh = update
	update()

	-- react to changes
	for _,id in ipairs(SKILLS) do
		lp:GetAttributeChangedSignal(levelAttr(id)):Connect(update)
	end
	lp:GetAttributeChangedSignal("Equip_Primary"):Connect(function()
		selectedId = lp:GetAttribute("Equip_Primary") or selectedId
		update()
	end)
	task.spawn(function()
		local plot = myPlot()
		if not plot then return end
		local function onAttrChanged()
			syncCombatLockOverlay()
		end
		plot:GetAttributeChangedSignal("CombatLocked"):Connect(onAttrChanged)
		plot:GetAttributeChangedSignal("AtIdle"):Connect(onAttrChanged)
		onAttrChanged()
	end)

	-- hold logic
	local HOLD_TIME = 3.0
	local holdTween, holdStart
	local function cancelHold() if holdTween then holdTween:Cancel() end; fill.Size = UDim2.fromScale(0,1); holdStart=nil end

	upgrade.MouseButton1Down:Connect(function()
		if lockedOverlay.Visible then play3D(SFX.deny, textPart.Position); return end
		local lv = getLevel(selectedId); if lv >= MAX_LEVEL then play3D(SFX.deny, textPart.Position); return end
		holdStart = os.clock()
		holdTween = Tween:Create(fill, TweenInfo.new(HOLD_TIME, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(1,1)})
		holdTween:Play()
	end)
	upgrade.MouseButton1Up:Connect(function()
		if not holdStart then return end
		local elapsed = os.clock() - holdStart
		cancelHold()
		if elapsed >= HOLD_TIME - 0.02 then
			RE_Buy:FireServer(selectedId)
			play3D(SFX.upgrade, textPart.Position, 0.9)
		else
			play3D(SFX.deny, textPart.Position)
		end
	end)
	upgrade.MouseLeave:Connect(cancelHold)
end

-- ---------- physical “Button” parts: click/hold + SFX ----------
local function attachWorldButtons(boardModel, picPart)
	if not boardModel then return end

	-- Clean any old prompts/detectors once
	for _,d in ipairs(boardModel:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end

	-- helper: case-insensitive find by name in descendants
	local function findByNameCI(name)
		local low = name:lower()
		for _,d in ipairs(boardModel:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower() == low then
				return d
			end
		end
	end

	-- 1) Preferred: explicit names (rename in Studio if you want this path)
	local leftUp   = findByNameCI("ButtonLeftUp")
	local leftDown = findByNameCI("ButtonLeftDown")

	local chosen = {}
	if leftUp and leftDown then
		chosen = { {part = leftUp,   isUp = true}, {part = leftDown, isUp = false} }
	else
		-- 2) Fallback: pick the two left-most among parts named exactly "Button"
		local refCF = (picPart and picPart.CFrame) or boardModel:GetPivot()
		local buttons = {}
		for _,d in ipairs(boardModel:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Button" then
				table.insert(buttons, d)
			end
		end
		if #buttons < 2 then return end
		table.sort(buttons, function(a,b)
			local ax = refCF:PointToObjectSpace(a.Position).X
			local bx = refCF:PointToObjectSpace(b.Position).X
			return ax < bx
		end)
		local a, b = buttons[1], buttons[2]
		-- decide which is upper vs lower by local Y
		local ay = refCF:PointToObjectSpace(a.Position).Y
		local by = refCF:PointToObjectSpace(b.Position).Y
		if ay > by then
			chosen = { {part=a,isUp=true}, {part=b,isUp=false} }
		else
			chosen = { {part=a,isUp=false}, {part=b,isUp=true} }
		end
	end

	-- wire helpers
	local function wire(p, isUp)
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 20
		cd.Parent = p

		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = isUp and "Next Skill" or "Prev Skill"
		pp.ObjectText = "Skill Board"
		pp.HoldDuration = 0
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 16
		pp.Parent = p

		local function step(delta)
			local plot = myPlot()
			local fighting = plot and (plot:GetAttribute("CombatLocked") == false)
			local atIdle   = plot and (plot:GetAttribute("AtIdle") == true)
			if fighting or (not atIdle) then
				play3D(SFX.deny, p.Position); return
			end
			-- ONLY affect slot #1 (active)
			local idx = table.find(SKILLS, selectedId) or 1
			idx = ((idx - 1 + delta) % #SKILLS) + 1
			selectedId = SKILLS[idx]
			slotSkills[1] = selectedId
			setSelected(selectedId)
			if forceTextRefresh then forceTextRefresh() end
			play3D(SFX.click, p.Position, 0.8)
		end

		cd.MouseClick:Connect(function() step(isUp and 1 or -1) end)
		pp.Triggered:Connect(function() step(isUp and 1 or -1) end)
	end

	for _,c in ipairs(chosen) do wire(c.part, c.isUp) end
end

-- ---------- boot ----------
local function boot()
	local plot = myPlot(); if not plot then return end
	local board, textPart, picPart = boardParts(plot); if not (board and textPart and picPart) then return end
	buildPicGui(picPart)
	buildTextGui(textPart)
	attachWorldButtons(board, picPart)
end

task.defer(function()
	for i=1,60 do
		boot()
		if textGui and picGui then break end
		task.wait(0.25)
	end
end)
