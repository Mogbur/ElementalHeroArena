local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local RE_Open = Remotes:WaitForChild("OpenCheckpointUI")
local RF_CP   = Remotes:WaitForChild("CheckpointRF")

local lp = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "CheckpointUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = lp:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position    = UDim2.fromScale(0.5, 0.5)
frame.Size        = UDim2.fromScale(0.36, 0.28)
frame.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
frame.BackgroundTransparency = 0.06
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = Color3.new(1,1,1)
title.Text = "Restart From Checkpoint"
title.Size = UDim2.new(1, -20, 0, 36)
title.Position = UDim2.new(0, 10, 0, 8)
title.Parent = frame

local list = Instance.new("Frame")
list.BackgroundTransparency = 1
list.Size = UDim2.new(1, -20, 1, -60)
list.Position = UDim2.new(0, 10, 0, 46)
list.Parent = frame

local layout = Instance.new("UIGridLayout", list)
layout.CellPadding = UDim2.fromOffset(8,8)
layout.CellSize    = UDim2.new(0, 80, 0, 44)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment   = Enum.VerticalAlignment.Top

local function mkBtn(wave, isDefault)
	local b = Instance.new("TextButton")
	b.Text = ("W%d"):format(wave)
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1,1,1)
	b.BackgroundColor3 = isDefault and Color3.fromRGB(65,120,220) or Color3.fromRGB(52,58,92)
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	b.Parent = list

	b.MouseButton1Click:Connect(function()
		local ok, res = pcall(function() return RF_CP:InvokeServer("choose", wave) end)
		if ok and res == true then
			gui.Enabled = false
		end
	end)
end

local function clearChildren(p)
	for _,c in ipairs(p:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

RE_Open.OnClientEvent:Connect(function(payload)
    if not payload or payload.from ~= "prompt_marker" then return end
	gui.Enabled = true
	clearChildren(list)
	local opts    = (payload and payload.options) or (function()
		local ok, seq = pcall(function() return RF_CP:InvokeServer("options") end)
		return (ok and seq) or {1}
	end)()
	local default = (payload and payload.default) or opts[#opts] or 1

	for _, w in ipairs(opts) do
		mkBtn(w, w == default)
	end
end)
