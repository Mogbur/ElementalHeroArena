local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local RF      = Remotes:WaitForChild("ForgeRF")
local RE      = Remotes:WaitForChild("OpenForgeUI")
local lp      = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ForgeUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = lp:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5,0.5)
frame.Position = UDim2.fromScale(0.5,0.5)
frame.Size = UDim2.fromScale(0.44,0.3)
frame.BackgroundColor3 = Color3.fromRGB(28,32,48)
frame.BackgroundTransparency = 0.06
frame.Visible = false
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,14)

local list = Instance.new("UIListLayout", frame)
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0,12)

local function mkBtn()
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromScale(0.45,0.8)
    b.TextScaled = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = Color3.fromRGB(52,58,92)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,12)
    local s = Instance.new("UIStroke", b); s.Thickness=2; s.Transparency=0.35
    b.Parent = frame
    return b
end

local coreBtn = mkBtn()
local utilBtn = mkBtn()
local closeBtn = mkBtn(); closeBtn.Text = "Close"

local currentWave = 1
local currentPlot

local function refresh()
    local offers = RF:InvokeServer("offers", currentWave)
    if not offers then return end
    coreBtn.Text = string.format("%s\nTier %d\n%d", offers.core.name, offers.core.tier, offers.core.price)
    utilBtn.Text = string.format("%s\n%d",       offers.util.name,          offers.util.price)
end

coreBtn.MouseButton1Click:Connect(function()
    if not currentPlot then return end
    RF:InvokeServer("buy", currentWave, {type="CORE", plot=currentPlot})
    refresh()
end)
utilBtn.MouseButton1Click:Connect(function()
    if not currentPlot then return end
    RF:InvokeServer("buy", currentWave, {type="UTIL", plot=currentPlot})
    refresh()
end)
closeBtn.MouseButton1Click:Connect(function() frame.Visible = false end)

-- server tells us to open (after pressing E at the shrine)
RE.OnClientEvent:Connect(function(plot)
    currentPlot = plot
    refresh()
    frame.Visible = true
end)

-- optional: keep an eye on your BoardHUD current wave (if you expose it),
-- or we can leave currentWave at default 1; the offer math is tiered anyway.
