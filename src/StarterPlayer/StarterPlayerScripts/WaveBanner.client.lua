-- WaveBanner.client.lua : world-space banner that bounces over your 06_BannerAnchor
local RS = game:GetService("ReplicatedStorage")
local TS = game:GetService("TweenService")

local Remotes = RS:WaitForChild("Remotes")
local RE      = Remotes:WaitForChild("WaveBanner")

local function makeBillboard(adornee: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WaveBillboard"
	bb.Adornee = adornee
	bb.AlwaysOnTop = false
	bb.LightInfluence = 1
	bb.Size = UDim2.fromOffset(680, 140)
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.MaxDistance = 2000
	bb.ResetOnSpawn = false
	bb.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1,1)
	root.Parent = bb

	local plate = Instance.new("Frame")
	plate.AnchorPoint = Vector2.new(0.5,0.5)
	plate.Position = UDim2.fromScale(0.5,0.5)
	plate.Size = UDim2.fromScale(0.86,0.7)
	plate.BackgroundColor3 = Color3.fromRGB(80,40,30)
	plate.BackgroundTransparency = 0.1
	plate.Parent = root
	Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 18)
	local stroke = Instance.new("UIStroke", plate)
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(30,15,10)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1,1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = Color3.new(1,1,1)
	lbl.TextStrokeTransparency = 0
	lbl.TextStrokeColor3 = Color3.new(0,0,0)
	lbl.Parent = plate

	-- “jump” tween by bobbing the offset
	local bob = TS:Create(bb, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true),
		{StudsOffset = Vector3.new(0, 9.2, 0)})
	bob:Play()

	return bb, bob
end

local function asText(payload)
	if payload.kind == "wave" then
		return string.format("Wave %d", payload.wave or 1)
	elseif payload.kind == "result" then
		return string.format("%s! (Wave %d)", payload.result or "Result", payload.wave or 1)
	end
	return "Wave"
end

RE.OnClientEvent:Connect(function(payload, anchorPart)
	if typeof(payload) ~= "table" then return end
	if not (anchorPart and anchorPart:IsA("BasePart")) then return end

	local hold = tonumber(payload.hold) or 5
	local text = asText(payload)

	local bb, tween = makeBillboard(anchorPart, text)
	task.delay(hold, function()
		if tween then pcall(function() tween:Cancel() end) end
		if bb then bb:Destroy() end
	end)
end)
