--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Spawned Weapon"
ENT.Author = "Rickster"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.TriggeEvent = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "eclass")
	self:NetworkVar("Entity", 0, "RagAttach")
end

function ENT:LookupBoneCached(model, name)
	if (model.cachedBones == nil) then
		model.cachedBones = {}
	end

	if (model.cachedBones[name] == nil) then
		model.cachedBones[name] = model:LookupBone(name)
	end

	return model.cachedBones[name]
end