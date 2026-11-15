--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Касса (повара)"
ENT.Author = "Mactavish"
ENT.Spawnable = true
ENT.AdminSpawnable = false
ENT.CanPack = true
ENT.ShowOnHud = true

function ENT:SetupDataTables()
	self:NetworkVar("Entity",0,"owning_ent")
	self:NetworkVar("Entity",1,"screen")
	self:NetworkVar("Float",0,"CustomPrice")
	self:NetworkVar("Float",1,"Space")
	self:NetworkVar("String",0,"StorageName")
end

ENT.SellTypes = {
	[INV_FOOD] = true,
}