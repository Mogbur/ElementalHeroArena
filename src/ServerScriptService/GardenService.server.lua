-- Planter crops -> cash + essence + hero XP
local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Shared  = RS:WaitForChild("Modules")
local Rojo    = SSS:WaitForChild("RojoServer")
local SrvMods = Rojo:WaitForChild("Modules")

local SeedConfig  = require(Shared:WaitForChild("SeedConfig"))
local Progression = require(SrvMods:WaitForChild("Progression"))

local DEFAULT_SEED_ID = "Blueberry"
local PlotState = {} -- [plot] = {capacity, plants={...}, visualFolder}

local function isPlot(m) return m:IsA("Model") and m.Name:match("^BasePlot%d+$") end
local function getGardenAnchor(plot)
	for _, c in ipairs(plot:GetChildren()) do
		if c:IsA("BasePart") and c.Name:lower():find("gardenanchor") then return c end
	end
end
local function getOwner(plot)
	local uid = plot:GetAttribute("OwnerUserId")
	if type(uid) ~= "number" or uid == 0 then return nil end
	for _, p in ipairs(Players:GetPlayers()) do if p.UserId == uid then return p end end
end
local function ensurePlotState(plot)
	if not PlotState[plot] then
		local folder = plot:FindFirstChild("Plants") or Instance.new("Folder")
		folder.Name = "Plants"; folder.Parent = plot
		PlotState[plot] = { capacity = plot:GetAttribute("GardenCapacity") or 6, plants = {}, visualFolder = folder }
	end; return PlotState[plot]
end
local function destroyPrompt(plot) local p=plot:FindFirstChild("GardenPromptPart"); if p then p:Destroy() end end
local function randomPointNear(anchor)
	local rx = (math.random()*2-1)*6; local rz = (math.random()*2-1)*4
	return anchor.CFrame * CFrame.new(rx,0,rz)
end

local function addRipeFX(model, seed)
	local fruit = model and model:FindFirstChild("Fruit"); if not (fruit and fruit:IsA("BasePart")) then return end
	if seed.element == "Fire" then
		local l=Instance.new("PointLight"); l.Color=Color3.fromRGB(255,140,60); l.Range=7; l.Brightness=2; l.Parent=fruit
	elseif seed.element == "Water" then
		local l=Instance.new("PointLight"); l.Color=Color3.fromRGB(80,140,255); l.Range=7; l.Brightness=1.8; l.Parent=fruit
	elseif seed.element == "Earth" then
		local l=Instance.new("PointLight"); l.Color=Color3.fromRGB(180,140,90); l.Range=7; l.Brightness=1.6; l.Parent=fruit
	end
end

local function makePlantModel(seed, cframe, parent)
	local m = Instance.new("Model"); m.Name = seed.display
	local pot = Instance.new("Part"); pot.Name="Pot"; pot.Shape=Enum.PartType.Cylinder
	pot.Color=seed.potColor; pot.Material=Enum.Material.Plastic; pot.Anchored=true; pot.CanCollide=false
	pot.Size=Vector3.new(seed.potSize.X, seed.potSize.Y, seed.potSize.Z); pot.CFrame=cframe+Vector3.new(0,pot.Size.Y/2,0); pot.Parent=m
	local stem=Instance.new("Part"); stem.Name="Stem"; stem.Shape=Enum.PartType.Cylinder
	stem.Color=seed.stemColor; stem.Material=Enum.Material.Grass; stem.Anchored=true; stem.CanCollide=false
	stem.Size=Vector3.new(0.22, seed.stemHeight, 0.22); stem.CFrame=pot.CFrame+Vector3.new(0,pot.Size.Y/2+stem.Size.Y/2,0); stem.Parent=m
	local fruit=Instance.new("Part"); fruit.Name="Fruit"; fruit.Shape=Enum.PartType.Ball
	fruit.Color=seed.fruitColorGrowing; fruit.Material=Enum.Material.SmoothPlastic; fruit.Anchored=true; fruit.CanCollide=false
	fruit.Size=Vector3.new(seed.fruitSize, seed.fruitSize, seed.fruitSize)
	fruit.CFrame=stem.CFrame+Vector3.new(0,stem.Size.Y/2+fruit.Size.Y/2,0); fruit.Parent=m
	m.PrimaryPart=pot; m.Parent=parent; return m
end

local function xpForSeed(seed) return 3 + math.floor((seed.growSeconds or 30)/10) + (seed.element and 1 or 0) end

local function updateRipeness(plot)
	local st=PlotState[plot]; if not st then return end
	for _, plant in ipairs(st.plants) do
		if not plant.ripe then
			local seed = Seeds[plant.seedId]
			if seed and (time() - plant.tPlanted) >= seed.growSeconds then
				plant.ripe = true
				local fruit = plant.model and plant.model:FindFirstChild("Fruit")
				if fruit and fruit:IsA("BasePart") then
					fruit.Color=seed.fruitColorRipe; fruit.Material=Enum.Material.Neon; fruit.Size=fruit.Size*1.2
				end
				plant.element = seed.element
				if seed.element then addRipeFX(plant.model, seed) end
			end
		end
	end
end

local function harvestAll(plot, owner)
	local st=PlotState[plot]; if not st then return 0 end
	local earned, keep, totalXP = 0, {}, 0
	local tally = {Fire=0, Water=0, Earth=0}
	for _, plant in ipairs(st.plants) do
		if plant.ripe then
			local seed = Seeds[plant.seedId]
			earned += (seed and seed.yieldCash or 0)
			totalXP += xpForSeed(seed)
			if seed and seed.yieldEssence and owner then
				local essFolder = owner:FindFirstChild("Essence")
				if essFolder then
					for element, amt in pairs(seed.yieldEssence) do
						tally[element]=(tally[element] or 0)+amt
						local stat = essFolder:FindFirstChild(element); if stat then stat.Value += amt end
					end
				end
			end
			if plant.model then plant.model:Destroy() end
		else
			table.insert(keep, plant)
		end
	end
	st.plants = keep

	if earned>0 and owner and owner:FindFirstChild("leaderstats") then
		local money=owner.leaderstats:FindFirstChild("Money"); if money then money.Value += earned end
	end
	if owner and totalXP>0 then Progression.AddXP(owner, totalXP) end

	local bestElem, bestAmt=nil,0
	for e,amt in pairs(tally) do if amt>bestAmt then bestElem, bestAmt = e, amt end end
	if bestElem then plot:SetAttribute("LastElement", bestElem) end

	return earned
end

local function plantOne(plot, owner)
	local st=ensurePlotState(plot)
	if #st.plants >= st.capacity then return false, "Garden is full" end
	local seed = Seeds[DEFAULT_SEED_ID]; if not seed then return false, "No seed selected" end
	local anchor = getGardenAnchor(plot); if not anchor then return false, "No garden" end
	local model = makePlantModel(seed, randomPointNear(anchor), st.visualFolder)
	table.insert(st.plants, {seedId=seed.id, tPlanted=time(), model=model, ripe=false, element=nil})
	return true
end

local function attachGardenPrompt(plot)
	destroyPrompt(plot)
	local owner = getOwner(plot); if not owner then return end
	local anchor = getGardenAnchor(plot); if not anchor then return end

	local part = Instance.new("Part")
	part.Name="GardenPromptPart"; part.Size=Vector3.new(2,2,2); part.Transparency=1; part.Anchored=true; part.CanCollide=false
	part.CFrame=anchor.CFrame; part.Parent=plot
	local prompt=Instance.new("ProximityPrompt")
	prompt.ActionText="Cultivate / Channel"; prompt.ObjectText="Garden"; prompt.HoldDuration=0; prompt.MaxActivationDistance=12
	prompt.RequiresLineOfSight=false; prompt.Parent=part

	prompt.Triggered:Connect(function(plr)
		if plr ~= owner then return end
		local st=ensurePlotState(plot); updateRipeness(plot)
		local anyRipe=false; for _,pl in ipairs(st.plants) do if pl.ripe then anyRipe=true break end end
		if anyRipe then
			local got=harvestAll(plot, owner)
			if got>0 then prompt.ObjectText=("+"..got.."$ Harvested"); task.delay(1.2, function() if prompt then prompt.ObjectText="Garden" end end) end
		else
			local ok,msg=plantOne(plot, owner)
			if not ok and msg then prompt.ObjectText=msg; task.delay(1.2, function() if prompt then prompt.ObjectText="Garden" end end) end
		end
	end)
end

local function clearPlot(plot)
	destroyPrompt(plot)
	local st=PlotState[plot]
	if st then for _,pl in ipairs(st.plants) do if pl.model then pl.model:Destroy() end end
		if st.visualFolder then st.visualFolder:ClearAllChildren() end; PlotState[plot]=nil end
end

local function hookPlot(plot)
	ensurePlotState(plot)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		if getOwner(plot) then attachGardenPrompt(plot) else clearPlot(plot) end
	end)
	if getOwner(plot) then attachGardenPrompt(plot) end
end

for _, m in ipairs(PLOTS:GetChildren()) do if isPlot(m) then hookPlot(m) end end
PLOTS.ChildAdded:Connect(function(m) if isPlot(m) then hookPlot(m) end end)

task.spawn(function()
	while true do for plot,_ in pairs(PlotState) do updateRipeness(plot) end task.wait(1) end
end)
