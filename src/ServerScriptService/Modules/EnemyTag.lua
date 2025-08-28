-- ServerScriptService/RojoServer/Modules/EnemyTag.lua
local CollectionService = game:GetService("CollectionService")

local M = {}

function M.attach(model: Instance)
	-- same behavior as the old in-template script
	task.defer(function()
		if model and model.Parent and not CollectionService:HasTag(model, "Enemy") then
			CollectionService:AddTag(model, "Enemy")
		end
	end)
end

function M.detach(model: Instance)
	if model and model.Parent and CollectionService:HasTag(model, "Enemy") then
		CollectionService:RemoveTag(model, "Enemy")
	end
end

return M
