local Players = game:GetService("Players")
Players.PlayerAdded:Connect(function(plr)
	local ls = Instance.new("Folder"); ls.Name="leaderstats"; ls.Parent=plr
	local money = Instance.new("IntValue"); money.Name="Money"; money.Value=0; money.Parent=ls
	local ess = Instance.new("Folder"); ess.Name="Essence"; ess.Parent=plr
	for _, n in ipairs({"Fire","Water","Earth"}) do
		local v=Instance.new("IntValue"); v.Name=n; v.Value=0; v.Parent=ess
	end
end)
