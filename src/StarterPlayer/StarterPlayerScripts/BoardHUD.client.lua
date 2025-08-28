-- BoardHUD.client.lua
-- Stylish arena board: shows Wave/Victory/Defeat and countdown.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local lp   = Players.LocalPlayer
local rems = ReplicatedStorage:WaitForChild("Remotes")
local RE   = rems:WaitForChild("WaveText")

local SHOW_IDLE_ON_JOIN = true
local PXS               = 44
local FORCE_FACE        = Enum.NormalId.Left

local IDLE_GRAD    = { Color3.fromRGB(60,60,70),   Color3.fromRGB(40,40,50) }
local WAVE_GRAD    = { Color3.fromRGB(65,115,220), Color3.fromRGB(30,55,120) }
local VICTORY_GRAD = { Color3.fromRGB(50,190,110), Color3.fromRGB(25,120,65) }
local DEFEAT_GRAD  = { Color3.fromRGB(200,80,80),  Color3.fromRGB(140,40,40) }
local HOLD_SEC     = 5

local function findMyPlot()
	local plots = workspace:WaitForChild("Plots")
	for _, m in ipairs(plots:GetChildren()) do
		if m:IsA("Model") and (m:GetAttribute("OwnerUserId") == lp.UserId) then
			return m
		end
	end
end

local function getBoardPart(plot)
	if not plot then return end
	local arena  = plot:FindFirstChild("Arena")
	local holder = (arena and arena:FindFirstChild("BoardHUD")) or plot:FindFirstChild("BoardHUD", true)
	if not holder then return end
	return holder:FindFirstChild("WaveBoardText") or holder:FindFirstChild("WaveBoardSurface_Left")
end

local function setGradient(frame, c1, c2)
	local g = frame:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient", frame)
	g.Rotation = 90
	g.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(1, c2),
	}
end

local bounceTween
local function startBounce(scaleObj)
	if bounceTween then bounceTween:Cancel() end
	bounceTween = TweenService:Create(
		scaleObj,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, -1, true),
		{ Scale = 1.04 }
	)
	bounceTween:Play()
end
local function stopBounce()
	if bounceTween then bounceTween:Cancel() end
	bounceTween = nil
end

-- put back the confetti burst for Victory
local function burstConfetti(parentPart)
	for i = 1, 2 do
		local pe = Instance.new("ParticleEmitter")
		pe.Parent = parentPart
		pe.Rate = 0
		pe.Speed = NumberRange.new(15, 28)
		pe.Lifetime = NumberRange.new(0.7, 1.1)
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-180, 180)
		pe.SpreadAngle = Vector2.new(45, 45)
		pe.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 230, 255)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 140, 200)),
		}
		pe.Size = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0.15),
		}
		pe.EmissionDirection = Enum.NormalId.Front
		pe.Acceleration = Vector3.new(0, 18, 0)
		pe:Emit(120)
		task.delay(1.2, function() if pe then pe.Enabled = false; pe:Destroy() end end)
	end
end

local gui, card, title, shadow, uiScale
local boardPart, plot = nil, nil

local function buildGui()
	if boardPart then
		local old = boardPart:FindFirstChild("BoardGui")
		if old then old:Destroy() end
	end
	if not boardPart then return end

	gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PXS
	gui.LightInfluence = 1
	gui.AlwaysOnTop = false
	gui.Face = FORCE_FACE
	gui.Parent = boardPart

	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position    = UDim2.fromScale(0.5, 0.5)
	card.Size        = UDim2.fromScale(0.86, 0.55)
	card.BackgroundTransparency = 0.12
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)
	local stroke = Instance.new("UIStroke", card); stroke.Thickness = 3; stroke.Transparency = 0.25; stroke.Color = Color3.new(0,0,0)

	shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.BackgroundTransparency = 1
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.5)
	shadow.Size = UDim2.fromScale(0.92, 0.61)
	shadow.Image = "rbxassetid://5028857084"
	shadow.ImageColor3 = Color3.new(0,0,0)
	shadow.ImageTransparency = 0.55
	shadow.ZIndex = 0
	shadow.Parent = gui

	title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.92, 0.8)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.new(1,1,1)
	title.TextStrokeColor3 = Color3.new(0,0,0)
	title.TextStrokeTransparency = 0.15
	title.ZIndex = 2
	title.Parent = card

	uiScale = Instance.new("UIScale", card)
	uiScale.Scale = 1

	setGradient(card, table.unpack(IDLE_GRAD))
	if SHOW_IDLE_ON_JOIN then
		local w = (plot and plot:GetAttribute("CurrentWave")) or 1
		title.Text = ("Wave %d"):format(w)
		card.Visible = true
	else
		title.Text = ""
		card.Visible = false
	end
end

local function setIdleText()
	local w = (plot and plot:GetAttribute("CurrentWave")) or 1
	setGradient(card, table.unpack(IDLE_GRAD))
	title.Text = ("Wave %d"):format(w)
	card.Visible = true
end
local function setWaveText(wave)
	setGradient(card, table.unpack(WAVE_GRAD))
	title.Text = ("Wave %d"):format(wave)
	card.Visible = true
end
local function setVictory(wave)
	setGradient(card, table.unpack(VICTORY_GRAD))
	title.Text = ("Victory!  (Wave %d)"):format(wave)
	card.Visible = true
end
local function setDefeat(wave)
	setGradient(card, table.unpack(DEFEAT_GRAD))
	title.Text = ("Defeat!   (Wave %d)"):format(wave)
	card.Visible = true
end

-- mount
task.spawn(function()
	local t0 = time()
	while not boardPart do
		plot = findMyPlot()
		boardPart = getBoardPart(plot)
		if boardPart then break end
		task.wait(0.25)
		if time() - t0 > 45 then break end
	end
	if boardPart then buildGui() end
end)

RE.OnClientEvent:Connect(function(payload)
	if not (gui and card and title) then return end

	if payload.kind == "countdown" then
		local n = tonumber(payload.n)
		setGradient(card, table.unpack(WAVE_GRAD))
		card.Visible = true
		if n == 3 then
			title.Text = "3"            -- FIX: show 3, not Wave
			startBounce(uiScale)
		elseif n == 2 then
			title.Text = "2"
		elseif n == 1 then
			title.Text = "1"
		elseif n == 0 then
			title.Text = "GO!"         -- FIX: show GO!
			stopBounce()
		end
		return
	end

	if payload.kind == "wave" then
		setWaveText(payload.wave)
		startBounce(uiScale)

	elseif payload.kind == "result" then
		stopBounce()
		if tostring(payload.result) == "Victory" then
			setVictory(payload.wave)
			burstConfetti(boardPart)
		else
			setDefeat(payload.wave)
		end
		task.delay(HOLD_SEC, function()
			if gui and card then setIdleText() end
		end)
	end
end)
