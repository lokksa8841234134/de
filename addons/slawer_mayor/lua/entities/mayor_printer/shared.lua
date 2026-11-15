--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Принтер"
ENT.Category = "DarkRP Mayor"
ENT.Spawnable = true

function ENT:SetupDataTables()
	self:NetworkVar("Float",0,"Space")
	self:NetworkVar("String",0,"StorageName")
end