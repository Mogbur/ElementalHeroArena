-- ReplicatedStorage/DamageNumbers (ModuleScript)
local TweenService = game:GetService("TweenService")

local DEFAULTS = {
	duration = 1.4,                 -- how long the float lasts
	rise     = 8,                   -- how high it floats
	offset   = Vector3.new(0, 3, 0),
	font     = Enum.Font.GothamBlack,
	sizeMul  = 1.0,                 -- 1.0 = normal, 1.6 for crits, etc.
}

local M = {}

-- part: BasePart to stick the number to (HRP, PrimaryPart, etc.)
-- value: number or string ("+25")
-- color: Color3 (optional)
-- opts:  optional {duration, rise, offset, font, sizeMul}
function M.pop(part, value, color, opts)
	if not (part and part.Parent) then return end
	opts = opts or DEFAULTS

	local w, h = 110 * (opts.sizeMul or 1), 44 * (opts.sizeMul or 1)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DMG"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(w, h)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffset = opts.offset or DEFAULTS.offset
	gui.ResetOnSpawn = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Font = opts.font or DEFAULTS.font
	label.TextScaled = true
	label.TextStrokeTransparency = 0.15
	label.TextColor3 = color or Color3.fromRGB(255, 235, 130)
	label.Text = tostring(value)
	label.Parent = gui

	-- float up & fade
	local dur  = opts.duration or DEFAULTS.duration
	local rise = opts.rise or DEFAULTS.rise
	local t1 = TweenService:Create(gui, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = (opts.offset or DEFAULTS.offset) + Vector3.new(0, rise, 0) })
	local t2 = TweenService:Create(label, TweenInfo.new(dur), { TextTransparency = 1, TextStrokeTransparency = 1 })
	t1:Play(); t2:Play()
	task.delay(dur + 0.1, function() if gui then gui:Destroy() end end)
end

return M
