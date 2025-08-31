-- ReplicatedStorage/Modules/DamageNumbers.lua

local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local RE_DMG  = Remotes and Remotes:FindFirstChild("DamageNumbers")

local M = {}

local DEFAULTS = {
	duration = 0.8,
	rise     = 5,
	offset   = Vector3.new(0, 2.4, 0),
	font     = Enum.Font.GothamBlack,
}

-- where: BasePart or Vector3
-- value: number or string
-- color: Color3
-- opts : {duration, rise, offset, sizeMul}
function M.pop(where, value, color, opts)
	opts = opts or {}
	local w, h = 110, 44
	if opts.sizeMul then
		w = math.floor(w * opts.sizeMul)
		h = math.floor(h * opts.sizeMul)
	end

	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(w, h)
	gui.StudsOffset = (opts.offset or DEFAULTS.offset)
	gui.ResetOnSpawn = false
	gui.Parent = workspace

	if typeof(where) == "Vector3" then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.Transparency = true, false, 1
		p.Size = Vector3.new(0.1,0.1,0.1)
		p.Position = where
		p.Parent = workspace
		gui.Adornee = p
		game:GetService("Debris"):AddItem(p, math.max(1, (opts.duration or DEFAULTS.duration) + 0.2))
	else
		gui.Adornee = where
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1,1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Font = opts.font or DEFAULTS.font
	label.TextScaled = true
	label.TextStrokeTransparency = 0.15
	label.TextColor3 = color or Color3.fromRGB(255,235,130)
	label.Text = tostring(value)
	label.Parent = gui

	local dur  = opts.duration or DEFAULTS.duration
	local rise = opts.rise     or DEFAULTS.rise

	local t1 = TweenService:Create(gui, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = (opts.offset or DEFAULTS.offset) + Vector3.new(0, rise, 0)
	})
	local t2 = TweenService:Create(label, TweenInfo.new(dur), {
		TextTransparency = 1, TextStrokeTransparency = 1
	})

	t1:Play(); t2:Play()
	task.delay(dur + 0.1, function() if gui then gui:Destroy() end end)
end

-- Optional client bus (so server can also RE_DMG:FireAllClients({...}))
if RunService:IsClient() and RE_DMG then
	RE_DMG.OnClientEvent:Connect(function(p)
		if not p then return end
		local where = p.part or p.pos
		local txt   = p.text or tostring(p.amount)
		local col   = p.color or Color3.new(1,1,1)
		M.pop(where, txt, col, p.opts)
	end)
end

return M
