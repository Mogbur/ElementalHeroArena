local ForgeService = require(script.Parent.Parent.Modules.ForgeService)

local function maybeUnlockForge(plot: Model)
	local wave = plot:GetAttribute("CurrentWave") or 0
	if wave >= 5 and not plot:GetAttribute("ForgeUnlocked") then
		ForgeService:SpawnElementalForge(plot) -- new function we add below
	end
end

local function hookPlot(plot: Instance)
	if not plot:IsA("Model") then return end
	plot:GetAttributeChangedSignal("CurrentWave"):Connect(function()
		maybeUnlockForge(plot)
	end)
	task.defer(function() maybeUnlockForge(plot) end) -- catch existing progress
end

local plotsFolder = workspace:FindFirstChild("Plots")
if plotsFolder then
	for _, p in ipairs(plotsFolder:GetChildren()) do hookPlot(p) end
	plotsFolder.ChildAdded:Connect(hookPlot)
end
